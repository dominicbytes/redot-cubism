// SPDX-License-Identifier: MIT
// Numeric motion oracle linked only to the user's pinned Cubism SDK.
#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>
#include <Effect/CubismBreath.hpp>
#include <Effect/CubismPose.hpp>
#include <ICubismAllocator.hpp>
#include <Id/CubismId.hpp>
#include <Id/CubismIdManager.hpp>
#include <Model/CubismMoc.hpp>
#include <Model/CubismModel.hpp>
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionQueueEntry.hpp>
#include <Motion/CubismExpressionMotion.hpp>
#include <Motion/CubismExpressionMotionManager.hpp>
#include <Physics/CubismPhysics.hpp>
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
    if (args.size() != 7 && args.size() != 10 && args.size() != 11) throw std::runtime_error("Pass model3.json, group, index, steps, fps, output.json, optional expression/physics/pose/breath");
    std::ofstream json(std::filesystem::u8path(args[6]));
    if (!json) throw std::runtime_error("Cannot write reference JSON");
    const auto manifest_path = std::filesystem::u8path(args[1]);
    const std::string& group = args[2];
    const int index = std::stoi(args[3]), steps = std::stoi(args[4]), fps = std::stoi(args[5]);
    const std::string expression = args.size() >= 10 ? args[7] : "";
    const bool with_physics = args.size() >= 10 && args[8] == "1";
    const bool with_pose = args.size() >= 10 && args[9] == "1";
    const bool with_breath = args.size() == 11 && args[10] == "1";
    for (size_t i = 8; i < args.size(); ++i)
        if (args[i] != "0" && args[i] != "1") throw std::runtime_error("Effect flags must be 0 or 1");
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
    std::unique_ptr<Csm::CubismExpressionMotion, decltype(&Csm::ACubismMotion::Delete)> expression_motion(nullptr, Csm::ACubismMotion::Delete);
    Csm::CubismExpressionMotionManager expressions;
    if (!expression.empty()) {
        for (int i = 0; i < settings.GetExpressionCount(); ++i) {
            if (expression != settings.GetExpressionName(i)) continue;
            const auto bytes = read(manifest_path.parent_path() / std::filesystem::u8path(settings.GetExpressionFileName(i)));
            expression_motion.reset(Csm::CubismExpressionMotion::Create(bytes.data(), bytes.size()));
            break;
        }
        if (!expression_motion) throw std::runtime_error("Expression is absent or rejected by SDK");
        expressions.StartMotion(expression_motion.get(), false);
    }
    std::unique_ptr<Csm::CubismPhysics, decltype(&Csm::CubismPhysics::Delete)> physics(nullptr, Csm::CubismPhysics::Delete);
    if (with_physics) {
        if (!*settings.GetPhysicsFileName()) throw std::runtime_error("Physics file is absent");
        const auto bytes = read(manifest_path.parent_path() / std::filesystem::u8path(settings.GetPhysicsFileName()));
        physics.reset(Csm::CubismPhysics::Create(bytes.data(), bytes.size()));
        if (!physics) throw std::runtime_error("SDK rejected physics");
    }
    std::unique_ptr<Csm::CubismPose, decltype(&Csm::CubismPose::Delete)> pose(nullptr, Csm::CubismPose::Delete);
    if (with_pose) {
        if (!*settings.GetPoseFileName()) throw std::runtime_error("Pose file is absent");
        const auto bytes = read(manifest_path.parent_path() / std::filesystem::u8path(settings.GetPoseFileName()));
        pose.reset(Csm::CubismPose::Create(bytes.data(), bytes.size()));
        if (!pose) throw std::runtime_error("SDK rejected pose");
    }
    std::unique_ptr<Csm::CubismBreath, decltype(&Csm::CubismBreath::Delete)> breath(nullptr, Csm::CubismBreath::Delete);
    if (with_breath) {
        // Standard R5 OpenGL sample profile, evaluated by SDK CubismBreath.
        auto* ids = Csm::CubismFramework::GetIdManager();
        Csm::csmVector<Csm::CubismBreath::BreathParameterData> profile;
        profile.PushBack({ids->GetId("ParamAngleX"), 0.0f, 15.0f, 6.5345f, 0.5f});
        profile.PushBack({ids->GetId("ParamAngleY"), 0.0f, 8.0f, 3.5345f, 0.5f});
        profile.PushBack({ids->GetId("ParamAngleZ"), 0.0f, 10.0f, 5.5345f, 0.5f});
        profile.PushBack({ids->GetId("ParamBodyAngleX"), 0.0f, 4.0f, 15.5345f, 0.5f});
        profile.PushBack({ids->GetId("ParamBreath"), 0.5f, 0.5f, 3.2345f, 0.5f});
        breath.reset(Csm::CubismBreath::Create());
        breath->SetParameters(profile);
    }
    model->SaveParameters();
    for (int step = 1; step <= steps; ++step) {
        model->LoadParameters();
        motion->UpdateParameters(model.get(), &entry, float(double(step) / fps));
        model->SaveParameters();
        if (expression_motion) expressions.UpdateMotion(model.get(), float(1.0 / fps));
        if (breath) breath->UpdateParameters(model.get(), float(1.0 / fps));
        if (physics) physics->Evaluate(model.get(), float(1.0 / fps));
        if (pose) pose->UpdateParameters(model.get(), float(1.0 / fps));
        model->Update();
    }
    json << std::setprecision(9) << "{\"steps\":" << steps << ",\"fps\":" << fps << ",\"expression\":";
    quoted(json, expression.c_str());
    json << ",\"physics\":" << (with_physics ? "true" : "false") << ",\"pose\":" << (with_pose ? "true" : "false")
         << ",\"breath\":" << (with_breath ? "true" : "false") << ",\"parameters\":{";
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
