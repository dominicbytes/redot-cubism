using System;
using System.Collections.Generic;
using Godot;

public partial class effects_probe : Node
{
    private const string Asset = "res://addons/gd_cubism/example/res/live2d/mao_pro_jp/runtime/Mao.model3.json";
    private readonly List<string> failures = new();
    private int entered;
    private int exited;

    public override void _Ready()
    {
        var modelNode = (Node2D)ClassDB.Instantiate("GDCubismUserModel");
        var targetNode = (Node)ClassDB.Instantiate("GDCubismEffectTargetPoint");
        var hitNode = (Node)ClassDB.Instantiate("GDCubismEffectHitArea");
        var breathNode = (Node)ClassDB.Instantiate("GDCubismEffectBreath");
        var blinkNode = (Node)ClassDB.Instantiate("GDCubismEffectEyeBlink");
        modelNode.AddChild(targetNode);
        modelNode.AddChild(hitNode);
        modelNode.AddChild(breathNode);
        modelNode.AddChild(blinkNode);
        AddChild(modelNode);

        var model = new GDCubismUserModelCS(modelNode);
        var target = new GDCubismEffectTargetPointCS(targetNode);
        var hit = new GDCubismEffectHitAreaCS(hitNode);
        var breath = new GDCubismEffectCS(breathNode);
        var blink = new GDCubismEffectCS(blinkNode);
        Godot.Collections.Array<GDCubismParameterCS> parameters = null;
        try
        {
            model.LoadMotions = false;
            model.LoadExpressions = false;
            model.PlaybackProcessMode = GDCubismUserModelCS.MotionProcessCallbackEnum.Manual;
            model.Assets = Asset;
            Check((bool)modelNode.Call("is_initialized"), "Mao model initialized");
            parameters = model.GetParameters();
            Check(parameters.Count > 0, "C# parameter enumeration");

            var angle = Find(parameters, "ParamAngleX");
            var eyeBall = Find(parameters, "ParamEyeBallX");
            var breathParam = Find(parameters, "ParamBreath");
            var leftEye = Find(parameters, "ParamEyeLOpen");
            var rightEye = Find(parameters, "ParamEyeROpen");
            Check(angle != null && eyeBall != null && breathParam != null && leftEye != null && rightEye != null,
                "C# parameter IDs");
            if (angle == null || eyeBall == null || breathParam == null || leftEye == null || rightEye == null)
                return;

            Check(angle.MinimumValue < angle.DefaultValue && angle.DefaultValue < angle.MaximumValue,
                "parameter range and default wrapper");
            Check(Math.Abs(angle.Value - angle.DefaultValue) < 0.1f, "parameter value wrapper initial state");

            // Effects initialize on the first model update; targets set before it are ignored.
            Step(model, 1);
            breath.Active = false;
            blink.Active = false;
            Check(!breath.Active && !blink.Active && target.Active, "base Active property over native effects");
            target.HeadAngleX = "ParamAngleX";
            target.HeadRange = 20f;
            target.BodyRange = 8f;
            target.EyesRange = 0.75f;
            Check(target.HeadAngleX == "ParamAngleX" && Math.Abs(target.HeadRange - 20f) < 0.001f
                && Math.Abs(target.BodyRange - 8f) < 0.001f && Math.Abs(target.EyesRange - 0.75f) < 0.001f,
                "target-point C# ID/range properties");
            Try("target-point EyesAngleX/Y native bindings", () =>
            {
                target.EyesAngleX = "ParamEyeBallX";
                target.EyesAngleY = "ParamEyeBallY";
                Check(target.EyesAngleX == "ParamEyeBallX" && target.EyesAngleY == "ParamEyeBallY",
                    "target-point eye ID round trip");
            });

            target.SetTarget(new Vector2(1, 0));
            Check(target.GetTarget().X >= 0 && target.GetTarget().X <= 1.001f,
                "target-point SetTarget/GetTarget");
            Step(model, 120);
            float rightAngle = angle.Value;
            float rightEyeBall = eyeBall.Value;
            target.SetTarget(new Vector2(-1, 0));
            Step(model, 120);
            float leftAngle = angle.Value;
            float leftEyeBall = eyeBall.Value;
            Check(rightAngle > 2f && leftAngle < -2f && rightEyeBall > 0.05f && leftEyeBall < -0.05f,
                $"target-point changes model parameters: angle={rightAngle:0.###}/{leftAngle:0.###}, eye={rightEyeBall:0.###}/{leftEyeBall:0.###}");
            GD.Print($"EFFECTS_TARGET_VALUES: angle={rightAngle:0.###}/{leftAngle:0.###}, eye={rightEyeBall:0.###}/{leftEyeBall:0.###}");
            target.Active = false;
            Step(model, 5);
            Check(Math.Abs(angle.Value - angle.DefaultValue) < 1f, "target-point Active=false suppresses parameter change");

            hit.Monitoring = true;
            Try("hit-area Monitoring getter", () => Check(hit.Monitoring, "hit-area Monitoring true round trip"));
            hit.Monitoring = false;
            Try("hit-area Monitoring false getter", () => Check(!hit.Monitoring, "hit-area Monitoring false round trip"));
            hit.Monitoring = true;
            hitNode.Connect("hit_area_entered", Callable.From<Node2D, string>(OnEntered));
            hitNode.Connect("hit_area_exited", Callable.From<Node2D, string>(OnExited));
            bool foundTriangle = TriangleCentroid(model, "HitAreaHead", out var inside);
            Check(foundTriangle, "known HitAreaHead drawable triangle");
            if (foundTriangle)
            {
                hit.SetTarget(inside);
                Check(hit.GetTarget().DistanceTo(inside) < 0.001f, "hit-area target round trip");
                var detail = hit.GetDetail(model, "HitAreaHead");
                Check(detail.ContainsKey("rect") && detail.ContainsKey("vertices"),
                    "hit-area detail contains drawable triangle at positive target");
                Step(model, 1);
                Check(entered > 0, "hit-area entered signal at drawable triangle");
                var rect = (Rect2)detail["rect"];
                var outside = rect.End + new Vector2(100000, 100000);
                hit.SetTarget(outside);
                var outsideDetail = hit.GetDetail(model, "HitAreaHead");
                Check(outsideDetail.ContainsKey("rect") && !outsideDetail.ContainsKey("vertices"),
                    "hit-area detail excludes triangle at negative target");
                Step(model, 1);
                Check(exited > 0, "hit-area exited signal at negative target");
                GD.Print($"EFFECTS_HIT_VALUES: entered={entered}, exited={exited}, inside={inside}, outside={outside}");
            }

            breath.Active = true;
            float breathMin = float.PositiveInfinity;
            float breathMax = float.NegativeInfinity;
            for (int i = 0; i < 240; i++)
            {
                model.Advance(1.0 / 60.0);
                breathMin = Math.Min(breathMin, breathParam.Value);
                breathMax = Math.Max(breathMax, breathParam.Value);
            }
            Check(breathMax - breathMin > 0.1f,
                $"native breath node accessible from C# changes ParamBreath: {breathMin:0.###}/{breathMax:0.###}");
            GD.Print($"EFFECTS_BREATH_VALUES: min={breathMin:0.###}, max={breathMax:0.###}");

            blink.Active = true;
            float eyeMin = float.PositiveInfinity;
            float eyeMax = float.NegativeInfinity;
            for (int i = 0; i < 480; i++)
            {
                model.Advance(1.0 / 60.0);
                eyeMin = Math.Min(eyeMin, Math.Min(leftEye.Value, rightEye.Value));
                eyeMax = Math.Max(eyeMax, Math.Max(leftEye.Value, rightEye.Value));
            }
            Check(eyeMin < 0.25f && eyeMax > 0.75f,
                $"native eye-blink node accessible from C# changes eye openness: {eyeMin:0.###}/{eyeMax:0.###}");
            GD.Print($"EFFECTS_BLINK_VALUES: min={eyeMin:0.###}, max={eyeMax:0.###}");
        }
        catch (Exception e)
        {
            failures.Add("probe exception: " + e.GetType().Name + ": " + e.Message);
        }
        finally
        {
            if (parameters != null)
                foreach (var parameter in parameters) parameter.Free();
            blink.Free();
            breath.Free();
            hit.Free();
            target.Free();
            model.Free();
            if (failures.Count == 0) GD.Print("EFFECTS_PROBE_PASS: target, hit, breath, blink, parameters");
            else GD.PrintErr("EFFECTS_PROBE_FAIL: " + string.Join(" | ", failures));
            GetTree().Quit(failures.Count == 0 ? 0 : 1);
        }
    }

    private void Check(bool passed, string name)
    {
        if (!passed) failures.Add(name);
    }

    private void Try(string name, Action action)
    {
        try { action(); }
        catch (Exception e) { failures.Add(name + ": " + e.GetType().Name + ": " + e.Message); }
    }

    private static GDCubismParameterCS Find(Godot.Collections.Array<GDCubismParameterCS> all, string id)
    {
        foreach (var parameter in all)
            if (parameter.Id == id) return parameter;
        return null;
    }

    private static void Step(GDCubismUserModelCS model, int frames)
    {
        for (int i = 0; i < frames; i++) model.Advance(1.0 / 60.0);
    }

    private static bool TriangleCentroid(GDCubismUserModelCS model, string id, out Vector2 point)
    {
        point = default;
        var meshes = model.GetMeshes();
        if (!meshes.ContainsKey(id)) return false;
        var instance = meshes[id].AsGodotObject() as MeshInstance2D;
        if (instance?.Mesh == null || instance.Mesh.GetSurfaceCount() == 0) return false;
        var arrays = instance.Mesh.SurfaceGetArrays(0);
        var vertices = (Godot.Collections.Array<Vector2>)arrays[(int)Mesh.ArrayType.Vertex];
        var indices = (Godot.Collections.Array<int>)arrays[(int)Mesh.ArrayType.Index];
        for (int i = 0; i + 2 < indices.Count; i += 3)
        {
            var a = vertices[indices[i]];
            var b = vertices[indices[i + 1]];
            var c = vertices[indices[i + 2]];
            if (Math.Abs((b - a).Cross(c - a)) < 0.0001f) continue;
            point = (a + b + c) / 3f;
            return true;
        }
        return false;
    }

    private void OnEntered(Node2D _, string id)
    {
        if (id == "HitAreaHead") entered++;
    }

    private void OnExited(Node2D _, string id)
    {
        if (id == "HitAreaHead") exited++;
    }
}
