// SPDX-License-Identifier: MIT
// Compile the user's SDK fragment shaders unchanged; never bundle SDK sources.
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>

using Color = std::array<float, 4>;

static GLuint compile(GLenum type, const std::string &source) {
    const GLuint shader = glCreateShader(type);
    const char *text = source.c_str();
    glShaderSource(shader, 1, &text, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096] = {};
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        throw std::runtime_error(log);
    }
    return shader;
}

static GLuint program(const std::string &path) {
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Cannot open SDK shader: " + path);
    const std::string fragment((std::istreambuf_iterator<char>(file)), {});
    const GLuint vs = compile(GL_VERTEX_SHADER,
        "#version 120\nvarying vec2 v_texCoord; varying vec4 v_clipPos;\n"
        "void main(){gl_Position=gl_Vertex;v_texCoord=vec2(0.5);v_clipPos=vec4(0.5,0.5,0.0,1.0);}\n");
    const GLuint fs = compile(GL_FRAGMENT_SHADER, fragment);
    const GLuint result = glCreateProgram();
    glAttachShader(result, vs);
    glAttachShader(result, fs);
    glLinkProgram(result);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(result, GL_LINK_STATUS, &ok);
    if (!ok) throw std::runtime_error("Cannot link SDK shader: " + path);
    return result;
}

static void color(GLuint shader, const char *name, const Color &value) {
    glUniform4fv(glGetUniformLocation(shader, name), 1, value.data());
}

template <typename T> static void json_array(const std::array<T, 4> &value) {
    std::cout << '[';
    for (int i = 0; i < 4; ++i) std::cout << (i ? "," : "") << +value[i];
    std::cout << ']';
}

int main(int argc, char **argv) {
    try {
        if (argc != 2) throw std::runtime_error("Pass the SDK OpenGL Shaders/Standard directory.");
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        EGLint major = 0, minor = 0;
        if (!eglInitialize(display, &major, &minor) || !eglBindAPI(EGL_OPENGL_API))
            throw std::runtime_error("Cannot initialize desktop OpenGL EGL display.");
        const EGLint attributes[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
        EGLConfig config;
        EGLint count = 0;
        if (!eglChooseConfig(display, attributes, &config, 1, &count) || count != 1)
            throw std::runtime_error("No RGBA8 pbuffer config.");
        const EGLint dimensions[] = {EGL_WIDTH, 4, EGL_HEIGHT, 4, EGL_NONE};
        EGLSurface surface = eglCreatePbufferSurface(display, config, dimensions);
        EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, nullptr);
        if (!eglMakeCurrent(display, surface, surface, context)) throw std::runtime_error("Cannot make EGL context current.");
        std::cerr << "GL renderer: " << glGetString(GL_RENDERER) << "\nGL version: " << glGetString(GL_VERSION) << '\n';
        GLint alpha_bits = 0;
        glGetIntegerv(GL_ALPHA_BITS, &alpha_bits);
        if (alpha_bits != 8) throw std::runtime_error("Expected an 8-bit alpha render target.");
        GLuint shaders[2][3];
        for (int premult = 0; premult < 2; ++premult) {
            for (int mask = 0; mask < 3; ++mask) {
                std::string name = "FragShaderSrc";
                if (mask) name += mask == 1 ? "Mask" : "MaskInverted";
                if (premult) name += "PremultipliedAlpha";
                shaders[premult][mask] = program(std::string(argv[1]) + "/" + name + ".frag");
            }
        }
        GLuint textures[2];
        glGenTextures(2, textures);
        for (int i = 0; i < 2; ++i) {
            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, textures[i]);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        }
        glViewport(0, 0, 4, 4);
        glDisable(GL_DITHER);
        glEnable(GL_BLEND);
        glBlendEquation(GL_FUNC_ADD);
        bool first = true;
        std::cout << "{\"cases\":[";
        for (int premult = 0; premult < 2; ++premult)
        for (int blend = 0; blend < 3; ++blend)
        for (int mask = 0; mask < 3; ++mask)
        for (int coverage : {0, 96, 255}) {
            if (!mask && coverage != 255) continue;
            for (int alpha : {0, 64, 128, 255})
            for (float opacity : {0.4f, 1.0f})
            for (float background_alpha : {0.0f, 0.5f, 1.0f})
            for (int effects = 0; effects < 2; ++effects) {
                std::array<unsigned char, 4> texel = {200, 100, 50, static_cast<unsigned char>(alpha)};
                if (premult) for (int i = 0; i < 3; ++i) texel[i] = (int(texel[i]) * (alpha + 1)) >> 8;
                const std::array<unsigned char, 4> clip = {static_cast<unsigned char>(255 - coverage), 0, 0, 255};
                glActiveTexture(GL_TEXTURE0);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, texel.data());
                glActiveTexture(GL_TEXTURE1);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, clip.data());
                const Color base = effects ? Color{0.8f, 0.6f, 0.9f, opacity} : Color{1, 1, 1, opacity};
                const Color modulate = effects ? Color{0.7f, 0.9f, 0.8f, 0.6f} : Color{1, 1, 1, 1};
                const Color multiply = effects ? Color{0.7f, 0.8f, 0.6f, 1} : Color{1, 1, 1, 1};
                const Color screen = effects ? Color{0.15f, 0.3f, 0.05f, 1} : Color{0, 0, 0, 1};
                const Color background = {0.2f, 0.4f, 0.7f, background_alpha};
                Color sdk_base;
                for (int i = 0; i < 4; ++i) sdk_base[i] = base[i] * modulate[i];
                if (premult) for (int i = 0; i < 3; ++i) sdk_base[i] *= sdk_base[3];
                const GLuint shader = shaders[premult][mask];
                glUseProgram(shader);
                glUniform1i(glGetUniformLocation(shader, "s_texture0"), 0);
                glUniform1i(glGetUniformLocation(shader, "s_texture1"), 1);
                color(shader, "u_baseColor", sdk_base);
                color(shader, "u_multiplyColor", multiply);
                color(shader, "u_screenColor", screen);
                color(shader, "u_channelFlag", {1, 0, 0, 0});
                // Same separate RGB/alpha factors as CubismShader_OpenGLES2.cpp.
                if (blend == 0) glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
                if (blend == 1) glBlendFuncSeparate(GL_ONE, GL_ONE, GL_ZERO, GL_ONE);
                if (blend == 2) glBlendFuncSeparate(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE);
                glClearColor(background[0] * background_alpha, background[1] * background_alpha,
                    background[2] * background_alpha, background_alpha);
                glClear(GL_COLOR_BUFFER_BIT);
                glBegin(GL_TRIANGLES);
                glVertex2f(-1, -1); glVertex2f(1, -1); glVertex2f(1, 1);
                glVertex2f(-1, -1); glVertex2f(1, 1); glVertex2f(-1, 1);
                glEnd();
                std::array<unsigned char, 4> pixel;
                glReadPixels(2, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.data());
                if (glGetError() != GL_NO_ERROR) throw std::runtime_error("OpenGL reference draw failed.");
                std::cout << (first ? "" : ",") << "{\"premultiplied\":" << (premult ? "true" : "false")
                    << ",\"blend\":" << blend << ",\"mask\":" << mask << ",\"coverage\":" << coverage << ",\"texel\":";
                json_array(texel);
                std::cout << ",\"base\":"; json_array(base);
                std::cout << ",\"modulate\":"; json_array(modulate);
                std::cout << ",\"multiply\":"; json_array(multiply);
                std::cout << ",\"screen\":"; json_array(screen);
                std::cout << ",\"background\":"; json_array(background);
                std::cout << ",\"expected\":"; json_array(pixel);
                std::cout << '}';
                first = false;
            }
        }
        std::cout << "]}\n";
        for (auto &variant : shaders) for (GLuint shader : variant) glDeleteProgram(shader);
        glDeleteTextures(2, textures);
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(display, context);
        eglDestroySurface(display, surface);
        eglTerminate(display);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
