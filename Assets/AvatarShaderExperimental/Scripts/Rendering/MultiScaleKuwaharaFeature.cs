using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class MultiScaleKuwaharaFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Shader shader;
        [Range(2, 16)] public float kernelSize = 5f;
        [Range(1, 18)] public float sharpness = 8f;
        [Range(1, 18)] public float hardness = 8f;
        [Range(0.1f, 2.0f)] public float alpha = 1.0f;
        [Range(1, 4)] public int numScales = 3;
        public float edgeThresholdMin = 0.02f;
        public float edgeThresholdMax = 0.2f;
        public LayerMask avatarLayer = 0; // Select avatar layer to mask abstraction, or "Nothing" for fullscreen
    }

    public Settings settings = new Settings();
    private MultiScaleKuwaharaPass m_ScriptablePass;

    public override void Create()
    {
        if (settings.shader == null)
            settings.shader = Shader.Find("NPR/MultiScaleKuwahara");

        if (settings.shader == null) return;

        m_ScriptablePass = new MultiScaleKuwaharaPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.shader == null) return;
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass?.Dispose();
    }

    class MultiScaleKuwaharaPass : ScriptableRenderPass
    {
        private Settings settings;
        private Material material;
        private Material maskMaterial;

        private RTHandle originalSceneRT;
        private RTHandle avatarMaskRT;
        private RTHandle tensorRT;
        private RTHandle tensorBlurRT;
        private RTHandle tempOutputRT;
        
        private RTHandle[] colorScales;
        private RTHandle[] tensorScales;
        private RTHandle[] kuwaharaScales;
        private RTHandle[] tempBlendScales;

        public MultiScaleKuwaharaPass(Settings settings)
        {
            this.settings = settings;
            this.renderPassEvent = settings.renderPassEvent;

            colorScales = new RTHandle[settings.numScales];
            tensorScales = new RTHandle[settings.numScales];
            kuwaharaScales = new RTHandle[settings.numScales];
            tempBlendScales = new RTHandle[settings.numScales - 1];
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (material == null && settings.shader != null) 
                material = CoreUtils.CreateEngineMaterial(settings.shader);
            
            if (maskMaterial == null) 
            {
                var maskShader = Shader.Find("Hidden/AvatarMaskCapture");
                if (maskShader != null)
                    maskMaterial = CoreUtils.CreateEngineMaterial(maskShader);
            }

            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;

            RenderingUtils.ReAllocateIfNeeded(ref originalSceneRT, desc, name: "_OriginalSceneRT");
            
            var maskDesc = desc;
            maskDesc.colorFormat = RenderTextureFormat.R8;
            RenderingUtils.ReAllocateIfNeeded(ref avatarMaskRT, maskDesc, name: "_AvatarMaskRT");

            var tensorDesc = desc;
            tensorDesc.colorFormat = RenderTextureFormat.ARGBHalf;
            RenderingUtils.ReAllocateIfNeeded(ref tensorRT, tensorDesc, name: "_TensorRT");
            RenderingUtils.ReAllocateIfNeeded(ref tensorBlurRT, tensorDesc, name: "_TensorBlurRT");

            for (int i = 0; i < settings.numScales; i++)
            {
                var scaleDesc = desc;
                scaleDesc.width = Mathf.Max(1, scaleDesc.width >> i);
                scaleDesc.height = Mathf.Max(1, scaleDesc.height >> i);
                
                var scaleTensorDesc = tensorDesc;
                scaleTensorDesc.width = Mathf.Max(1, scaleTensorDesc.width >> i);
                scaleTensorDesc.height = Mathf.Max(1, scaleTensorDesc.height >> i);

                RenderingUtils.ReAllocateIfNeeded(ref colorScales[i], scaleDesc, name: "_ColorScale" + i);
                RenderingUtils.ReAllocateIfNeeded(ref tensorScales[i], scaleTensorDesc, name: "_TensorScale" + i);
                RenderingUtils.ReAllocateIfNeeded(ref kuwaharaScales[i], scaleDesc, name: "_KuwaharaScale" + i);
                
                if (i < settings.numScales - 1)
                {
                    RenderingUtils.ReAllocateIfNeeded(ref tempBlendScales[i], scaleDesc, name: "_TempBlendScale" + i);
                }
            }
            RenderingUtils.ReAllocateIfNeeded(ref tempOutputRT, desc, name: "_TempOutputRT");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (material == null) return;
            
            var source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            if (source == null || source.rt == null) return;

            CommandBuffer cmd = CommandBufferPool.Get("MultiScaleKuwahara");

            // Draw mask using the correct Avatar Mask Capture shader and keeping depth buffer bound
            if (settings.avatarLayer != 0 && maskMaterial != null)
            {
                Blitter.BlitCameraTexture(cmd, source, originalSceneRT);

                var maskCmd = CommandBufferPool.Get("KuwaharaMask");
                maskCmd.SetRenderTarget(avatarMaskRT, renderingData.cameraData.renderer.cameraDepthTargetHandle);
                maskCmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(maskCmd);
                CommandBufferPool.Release(maskCmd);

                var sortSettings = new SortingSettings(renderingData.cameraData.camera) { criteria = SortingCriteria.CommonOpaque };
                var drawSettings = new DrawingSettings(new ShaderTagId("UniversalForward"), sortSettings)
                {
                    overrideMaterial = maskMaterial,
                    overrideMaterialPassIndex = 0
                };
                drawSettings.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
                drawSettings.SetShaderPassName(2, new ShaderTagId("SRPDefaultUnlit"));

                var filterSettings = new FilteringSettings(RenderQueueRange.opaque, settings.avatarLayer);
                context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filterSettings);
            }

            // 1. Structure Tensor & Gaussian Blur setup
            Blitter.BlitCameraTexture(cmd, source, tensorRT, material, 0); // Structure Tensor
            cmd.SetGlobalVector("_BlurDirection", new Vector4(1, 0, 0, 0));
            Blitter.BlitCameraTexture(cmd, tensorRT, tensorBlurRT, material, 1); // Tensor Blur (Horizontal)
            cmd.SetGlobalVector("_BlurDirection", new Vector4(0, 1, 0, 0));
            Blitter.BlitCameraTexture(cmd, tensorBlurRT, tensorRT, material, 1); // Tensor Blur (Vertical)

            // 2. Compute Filter down across multiple scale resolutions (multi-scale abstraction)
            for (int i = 0; i < settings.numScales; i++)
            {
                if (i == 0) Blitter.BlitCameraTexture(cmd, source, colorScales[i]);
                else Blitter.BlitCameraTexture(cmd, colorScales[i - 1], colorScales[i]);

                if (i == 0) Blitter.BlitCameraTexture(cmd, tensorRT, tensorScales[i]);
                else Blitter.BlitCameraTexture(cmd, tensorScales[i - 1], tensorScales[i]);
                
                material.SetFloat("_KernelSize", settings.kernelSize);
                material.SetFloat("_Sharpness", settings.sharpness);
                material.SetFloat("_Hardness", settings.hardness);
                material.SetFloat("_Alpha", settings.alpha);
                
                cmd.SetGlobalTexture("_StructureTensor", tensorScales[i]);
                Blitter.BlitCameraTexture(cmd, colorScales[i], kuwaharaScales[i], material, 2); // Kuwahara Pass
            }

            // 3. Blend scales from coarsest resolution layers down to fine edges
            RTHandle currentBlend = kuwaharaScales[settings.numScales - 1];
            for (int i = settings.numScales - 2; i >= 0; i--)
            {
                material.SetFloat("_EdgeThresholdMin", settings.edgeThresholdMin);
                material.SetFloat("_EdgeThresholdMax", settings.edgeThresholdMax);
                cmd.SetGlobalTexture("_CoarseTex", currentBlend);
                cmd.SetGlobalTexture("_StructureTensor", tensorScales[i]);
                
                RTHandle tempBlend = tempBlendScales[i];
                
                Blitter.BlitCameraTexture(cmd, kuwaharaScales[i], tempBlend, material, 3); // Multi-Scale Blend Pass
                currentBlend = tempBlend;
            }

            // 4. Output back to camera using the masking layer logic
            if (settings.avatarLayer != 0 && maskMaterial != null)
            {
                cmd.SetGlobalTexture("_OriginalScene", originalSceneRT);
                cmd.SetGlobalTexture("_AvatarMask", avatarMaskRT);
                
                Blitter.BlitCameraTexture(cmd, currentBlend, tempOutputRT);
                Blitter.BlitCameraTexture(cmd, tempOutputRT, source, material, 4);
            }
            else
            {
                Blitter.BlitCameraTexture(cmd, currentBlend, source);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            originalSceneRT?.Release();
            avatarMaskRT?.Release();
            tensorRT?.Release();
            tensorBlurRT?.Release();
            tempOutputRT?.Release();
            
            if (colorScales != null) {
                for (int i = 0; i < colorScales.Length; i++) {
                    colorScales[i]?.Release();
                    tensorScales[i]?.Release();
                    kuwaharaScales[i]?.Release();
                    if (i < tempBlendScales.Length) tempBlendScales[i]?.Release();
                }
            }
            
            CoreUtils.Destroy(material);
            CoreUtils.Destroy(maskMaterial);
        }
    }
}