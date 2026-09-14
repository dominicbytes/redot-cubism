// SPDX-License-Identifier: MIT
// Numeric motion oracle linked only to the user's pinned Cubism SDK.
#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>
#include <ICubismAllocator.hpp>
#include <Id/CubismId.hpp>
#include <Model/CubismMoc.hpp>
#include <Model/CubismModel.hpp>
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionQueueEntry.hpp>
#include <Rendering/CubismRenderer.hpp>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <codecvt>
#include <locale>
#include <malloc.h>
#endif

namespace Csm = Live2D::Cubism::Framework;
// This executable evaluates parameters only and never creates a renderer.
Csm::Rendering::CubismRenderer* Csm::Rendering::CubismRenderer::Create(Csm::csmUint32, Csm::csmUint32) { return nullptr; }
void Csm::Rendering::CubismRenderer::StaticRelease() {}

class Allocator : public Csm::ICubismAllocator {
public:
    void* Allocate(const Csm::csmSizeType size) override { return std::malloc(size); }
    void Deallocate(void* memory) override { std::free(memory); }
    void* AllocateAligned(const Csm::csmSizeType size, const Csm::csmUint32 alignment) override {
#ifdef _WIN32
        return _aligned_malloc(size, alignment);
#else
        void* memory = nullptr;
        return posix_memalign(&memory, alignment, size) == 0 ? memory : nullptr;
#endif
    }
    void DeallocateAligned(void* memory) override {
#ifdef _WIN32
        _aligned_free(memory);
#else
        std::free(memory);
#endif
    }
};

static std::vector<Csm::csmByte> read(const std::filesystem::path& path) {
    const auto size = std::filesystem::file_size(path);
    if (size == 0 || size > 512 * 1024 * 1024) throw std::runtime_error("Invalid fixture size");
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Missing SDK fixture file");
    std::vector<Csm::csmByte> bytes{std::istreambuf_iterator<char>(input), {}};
    if (bytes.size() != size) throw std::runtime_error("Incomplete fixture read");
    return bytes;
}

static void quoted(std::ostream& json, const char* text) {
    json << '"';
    for (const unsigned char c : std::string(text)) {
        if (c == '"' || c == '\\') json << '\\' << c;
        else if (c < 32) json << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << int(c) << std::dec;
        else json << c;
    }
    json << '"';
}

static void evaluate(const std::vector<std::string>& args) {
    if (args.size() != 7) throw std::runtime_error("Pass model3.json, group, index, steps, fps, output.json");
    std::ofstream json(std::filesystem::u8path(args[6]));
    if (!json) throw std::runtime_error("Cannot write reference JSON");
    const auto manifest_path = std::filesystem::u8path(args[1]);
    const std::string& group = args[2];
    const int index = std::stoi(args[3]), steps = std::stoi(args[4]), fps = std::stoi(args[5]);
    if (index < 0 || steps < 1 || steps > 36000 || fps < 1 || fps > 240) throw std::runtime_error("Invalid sample arguments");
    const auto manifest = read(manifest_path);
    Csm::CubismModelSettingJson settings(manifest.data(), manifest.size());
    if (index >= settings.GetMotionCount(group.c_str())) throw std::runtime_error("Motion is absent from manifest");
    const auto moc_bytes = read(manifest_path.parent_path() / std::filesystem::u8path(settings.GetModelFileName()));
    std::unique_ptr<Csm::CubismMoc, decltype(&Csm::CubismMoc::Delete)> moc(
        Csm::CubismMoc::Create(moc_bytes.data(), moc_bytes.size(), true), Csm::CubismMoc::Delete);
    if (!moc) throw std::runtime_error("SDK rejected MOC");
    const auto destroy_model = [&](Csm::CubismModel* model) { moc->DeleteModel(model); };
    std::unique_ptr<Csm::CubismModel, decltype(destroy_model)> model(moc->CreateModel(), destroy_model);
    if (!model) throw std::runtime_error("SDK could not create model");
    const auto motion_bytes = read(manifest_path.parent_path() / std::filesystem::u8path(settings.GetMotionFileName(group.c_str(), index)));
    std::unique_ptr<Csm::CubismMotion, decltype(&Csm::ACubismMotion::Delete)> motion(
        Csm::CubismMotion::Create(motion_bytes.data(), motion_bytes.size()), Csm::ACubismMotion::Delete);
    if (!motion) throw std::runtime_error("SDK rejected motion");
    const float fade_in = settings.GetMotionFadeInTimeValue(group.c_str(), index);
    const float fade_out = settings.GetMotionFadeOutTimeValue(group.c_str(), index);
    if (fade_in >= 0) motion->SetFadeInTime(fade_in);
    if (fade_out >= 0) motion->SetFadeOutTime(fade_out);
    Csm::csmVector<Csm::CubismIdHandle> blink, lip;
    for (int i = 0; i < settings.GetEyeBlinkParameterCount(); ++i) blink.PushBack(settings.GetEyeBlinkParameterId(i));
    for (int i = 0; i < settings.GetLipSyncParameterCount(); ++i) lip.PushBack(settings.GetLipSyncParameterId(i));
    motion->SetEffectIds(blink, lip);
    // Compare one non-looping playback; loop/event policy has separate tests.
    motion->SetLoop(false);
    Csm::CubismMotionQueueEntry entry;
    motion->SetupMotionQueueEntry(&entry, 0.0f);
    model->SaveParameters();
    for (int step = 1; step <= steps; ++step) {
        model->LoadParameters();
        motion->UpdateParameters(model.get(), &entry, float(double(step) / fps));
        model->SaveParameters();
        model->Update();
    }
    json << std::setprecision(9) << "{\"steps\":" << steps << ",\"fps\":" << fps << ",\"parameters\":{";
    for (int i = 0; i < model->GetParameterCount(); ++i) {
        if (i) json << ',';
        quoted(json, model->GetParameterId(i)->GetString().GetRawString());
        json << ':' << model->GetParameterValue(i);
    }
    json << "},\"parts\":{";
    for (int i = 0; i < model->GetPartCount(); ++i) {
        if (i) json << ',';
        quoted(json, model->GetPartId(i)->GetString().GetRawString());
        json << ':' << model->GetPartOpacity(i);
    }
    json << "}}\n";
}

static int run(const std::vector<std::string>& args) {
    Allocator allocator;
    Csm::CubismFramework::Option option{};
    option.LoggingLevel = Csm::CubismFramework::Option::LogLevel_Off;
    if (!Csm::CubismFramework::StartUp(&allocator, &option)) return 1;
    Csm::CubismFramework::Initialize();
    int code = 0;
    try { evaluate(args); }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; code = 1; }
    Csm::CubismFramework::Dispose();
    Csm::CubismFramework::CleanUp();
    return code;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> utf8;
    std::vector<std::string> args;
    for (int i = 0; i < argc; ++i) args.push_back(utf8.to_bytes(argv[i]));
    return run(args);
}
#else
int main(int argc, char** argv) { return run(std::vector<std::string>(argv, argv + argc)); }
#endif
