using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// Generic single-pass blit Renderer Feature.
/// Assign any of the NPR/Hidden/PostProcess shaders to the Material field,
/// then add this feature to your URP Renderer asset.
public class NPRBlitFeature : ScriptableRendererFeature
{
    [Tooltip("Material using one of the NPR shaders (Kuwahara, Sobel, Halftone etc.)")]
    public Material material;

    [Tooltip("When in the frame to run the effect")]
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;

    private NPRBlitPass _pass;

    public override void Create()
    {
        _pass = new NPRBlitPass(material, renderPassEvent);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (material == null) return;
        _pass.Setup(material, renderPassEvent);
        renderer.EnqueuePass(_pass);
    }
}

public class NPRBlitPass : ScriptableRenderPass
{
    private Material _material;
    private RTHandle _tempRT;
    private const string k_ProfilerTag = "NPR Blit Pass";

    public NPRBlitPass(Material mat, RenderPassEvent evt)
    {
        _material = mat;
        renderPassEvent = evt;
    }

    public void Setup(Material mat, RenderPassEvent evt)
    {
        _material = mat;
        renderPassEvent = evt;
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        RenderingUtils.ReAllocateIfNeeded(ref _tempRT, desc, name: "_NPRTemp");
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (_material == null) return;

        var cmd = CommandBufferPool.Get(k_ProfilerTag);
        var source = renderingData.cameraData.renderer.cameraColorTargetHandle;

        Blitter.BlitCameraTexture(cmd, source, _tempRT, _material, 0);
        Blitter.BlitCameraTexture(cmd, _tempRT, source);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        _tempRT?.Release();
    }
}
