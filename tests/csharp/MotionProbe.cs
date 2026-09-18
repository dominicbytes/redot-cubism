using System;
using Godot;

public partial class MotionProbe : Node
{
    private const string ModelPath = "res://addons/gd_cubism/example/res/live2d/mao_pro_jp/runtime/Mao.model3.json";
    private int checks;

    private void Check(bool condition, string label)
    {
        checks++;
        if (!condition)
            throw new InvalidOperationException(label);
    }

    private static GDCubismParameterCS Parameter(Godot.Collections.Array<GDCubismParameterCS> parameters, string id)
    {
        foreach (GDCubismParameterCS parameter in parameters)
        {
            if (parameter.Id == id)
                return parameter;
        }
        throw new InvalidOperationException($"Parameter missing: {id}");
    }

    private static int QueueCount(GDCubismUserModelCS model)
    {
        using var entries = model.GetCubismMotionQueueEntries();
        return entries.Count;
    }

    public override async void _Ready()
    {
        GDCubismUserModelCS model = null;
        Node2D native = null;
        Godot.Collections.Array<GDCubismParameterCS> parameters = null;
        Action onFinished = null;
        GDCubismUserModelCS.MotionEventEventHandler onEvent = null;
        bool finishedConnected = false;
        bool eventConnected = false;
        int exitCode = 0;
        string result = null;
        try
        {
            model = new GDCubismUserModelCS();
            native = model.GetInternalObject();
            AddChild(native);
            model.PlaybackProcessMode = GDCubismUserModelCS.MotionProcessCallbackEnum.Manual;
            model.PhysicsEvaluate = false;
            model.PoseUpdate = false;
            model.LoadMotions = true;
            model.LoadExpressions = true;
            model.Assets = ModelPath;
            Check(native.Call("is_initialized").AsBool(), "Mao model loads");
            Check(model.PlaybackProcessMode == GDCubismUserModelCS.MotionProcessCallbackEnum.Manual,
                "manual playback property round trip");
            Check(model.LoadMotions && model.LoadExpressions, "load flags round trip");

            var motions = model.GetMotions();
            Check(motions.ContainsKey("Idle") && motions["Idle"] == 2, "Idle catalog count");
            Check(motions.ContainsKey("TapBody") && motions["TapBody"] == 6, "TapBody catalog count");
            var expressions = model.GetExpressions();
            Check(expressions.Count == 8 && expressions.Contains("exp_02"), "expression catalog");

            parameters = model.GetParameters();
            var smile = Parameter(parameters, "ParamEyeLSmile");
            float smileBefore = smile.Value;
            model.StartExpression("exp_02");
            for (int i = 0; i < 12; i++) model.Advance(0.1);
            float smileDuring = smile.Value;
            Check(smileDuring > smileBefore + 0.5f, "StartExpression changes smile parameter");
            model.StopExpression();
            for (int i = 0; i < 12; i++) model.Advance(0.1);
            float smileAfter = smile.Value;
            Check(smileAfter < smileDuring - 0.4f, "StopExpression removes smile influence");

            var angle = Parameter(parameters, "ParamAngleX");
            model.StartMotionLoop("TapBody", 3, GDCubismUserModelCS.PriorityEnum.PriorityForce, true, false);
            Check(QueueCount(model) > 0, "loop enters motion queue");
            float angleMin = angle.Value;
            float angleMax = angle.Value;
            for (int i = 0; i < 28; i++)
            {
                model.Advance(0.1);
                angleMin = Math.Min(angleMin, angle.Value);
                angleMax = Math.Max(angleMax, angle.Value);
            }
            Check(angleMax - angleMin > 5.0f, "StartMotionLoop changes angle parameter");
            Check(QueueCount(model) > 0, "loop remains queued");
            model.StopMotion();
            Check(QueueCount(model) == 0, "StopMotion empties motion queue");
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

            int finished = 0;
            int events = 0;
            string eventValue = null;
            onEvent = value =>
            {
                eventValue = value;
                events++;
            };
            onFinished = () => finished++;
            model.MotionFinished += onFinished;
            finishedConnected = true;
            model.MotionEvent += onEvent;
            eventConnected = true;
            model.StartMotion("TapBody", 3, GDCubismUserModelCS.PriorityEnum.PriorityForce);
            Check(QueueCount(model) > 0, "one-shot enters motion queue");
            for (int i = 0; i < 90; i++) model.Advance(0.1);
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            Check(QueueCount(model) == 0, "one-shot completes");
            Check(finished == 1, "MotionFinished delivered once");
            Check(events == 1, $"MotionEvent delivered once (count={events}, value={eventValue})");
            Check(eventValue == "csharp-wrapper-event-😀", "MotionEvent preserves Unicode payload");
            model.MotionEvent -= onEvent;
            eventConnected = false;
            model.StartMotion("TapBody", 3, GDCubismUserModelCS.PriorityEnum.PriorityForce);
            for (int i = 0; i < 3; i++) model.Advance(0.1);
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            Check(events == 1, "MotionEvent unsubscribe removes callback");
            model.StopMotion();

            result = $"MOTION_PROBE_PASS: checks={checks} smile={smileBefore:F3}/{smileDuring:F3}/{smileAfter:F3} angle_range={angleMin:F3}..{angleMax:F3} events={events}";
        }
        catch (Exception ex)
        {
            GD.PrintErr($"MOTION_PROBE_FAIL: checks={checks} {ex}");
            exitCode = 1;
        }
        finally
        {
            if (model != null && GodotObject.IsInstanceValid(model))
            {
                if (eventConnected) model.MotionEvent -= onEvent;
                if (finishedConnected) model.MotionFinished -= onFinished;
            }
            if (parameters != null)
            {
                foreach (GDCubismParameterCS parameter in parameters)
                    if (GodotObject.IsInstanceValid(parameter)) parameter.Free();
                parameters.Clear();
            }
            if (native != null && GodotObject.IsInstanceValid(native))
                native.Free();
            if (model != null && GodotObject.IsInstanceValid(model))
                model.Free();
        }
        if (result != null) GD.Print(result);
        GetTree().Quit(exitCode);
    }
}
