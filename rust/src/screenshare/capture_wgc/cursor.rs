//! The cursor drawn into a duplicated screen's pictures on the GPU.
//!
//! Its shape comes from the duplication each time it changes (`dxgi`), into
//! two small textures (`cursor_shape`), and each picture then gets it with two
//! draws. GDI drawing into the picture itself, as this did before, had to wait
//! for the GPU to finish with the picture first: 8–15 ms on a still Windows 10
//! desktop, 33–47 ms beside an uncapped game, which held the share to 21 fps
//! (Nov 19 2026). Nothing here waits for the GPU.

use crate::screenshare::cursor_shape::ShapeImages;
use std::sync::OnceLock;
use windows::core::{s, Error, Result, PCSTR};
use windows::Win32::Foundation::{E_FAIL, POINT};
use windows::Win32::Graphics::Direct3D::Fxc::{D3DCompile, D3DCOMPILE_OPTIMIZATION_LEVEL3};
use windows::Win32::Graphics::Direct3D::{ID3DBlob, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP};
use windows::Win32::Graphics::Direct3D11::{
    ID3D11BlendState, ID3D11Device, ID3D11DeviceContext, ID3D11PixelShader, ID3D11RasterizerState,
    ID3D11RenderTargetView, ID3D11SamplerState, ID3D11ShaderResourceView, ID3D11VertexShader,
    D3D11_BIND_SHADER_RESOURCE, D3D11_BLEND, D3D11_BLEND_DESC, D3D11_BLEND_INV_DEST_COLOR,
    D3D11_BLEND_INV_SRC_ALPHA, D3D11_BLEND_INV_SRC_COLOR, D3D11_BLEND_ONE, D3D11_BLEND_OP_ADD,
    D3D11_BLEND_SRC_ALPHA, D3D11_BLEND_ZERO, D3D11_COLOR_WRITE_ENABLE_ALL, D3D11_COMPARISON_NEVER,
    D3D11_CULL_NONE, D3D11_FILL_SOLID, D3D11_FILTER_MIN_MAG_MIP_POINT, D3D11_RASTERIZER_DESC,
    D3D11_RENDER_TARGET_BLEND_DESC, D3D11_SAMPLER_DESC, D3D11_SUBRESOURCE_DATA,
    D3D11_TEXTURE2D_DESC, D3D11_TEXTURE_ADDRESS_CLAMP, D3D11_USAGE_IMMUTABLE, D3D11_VIEWPORT,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC};

/// A quad over the viewport, which is set to the cursor's place, sampling its
/// shape a pixel for a pixel.
const SHADERS: &str = r"
Texture2D shape : register(t0);
SamplerState nearest : register(s0);
struct Corner { float4 at : SV_Position; float2 uv : TEXCOORD0; };
Corner vs(uint id : SV_VertexID) {
    Corner c;
    c.uv = float2(id & 1, id >> 1);
    c.at = float4(c.uv.x * 2 - 1, 1 - c.uv.y * 2, 0, 1);
    return c;
}
float4 ps(Corner c) : SV_Target { return shape.Sample(nearest, c.uv); }
";

/// The two shaders' bytecode, compiled once a process.
fn bytecode() -> Option<&'static (Vec<u8>, Vec<u8>)> {
    static CODE: OnceLock<Option<(Vec<u8>, Vec<u8>)>> = OnceLock::new();
    CODE.get_or_init(|| {
        match (
            compile(s!("vs"), s!("vs_4_0")),
            compile(s!("ps"), s!("ps_4_0")),
        ) {
            (Ok(vs), Ok(ps)) => Some((vs, ps)),
            (Err(e), _) | (_, Err(e)) => {
                log::warn!("capture: the cursor's shaders did not compile: {e}");
                None
            }
        }
    })
    .as_ref()
}

fn compile(entry: PCSTR, target: PCSTR) -> std::result::Result<Vec<u8>, String> {
    let mut code: Option<ID3DBlob> = None;
    let mut errors: Option<ID3DBlob> = None;
    // SAFETY: the source outlives the call; both blobs are written by it.
    let compiled = unsafe {
        D3DCompile(
            SHADERS.as_ptr().cast(),
            SHADERS.len(),
            s!("cursor"),
            None,
            None,
            entry,
            target,
            D3DCOMPILE_OPTIMIZATION_LEVEL3,
            0,
            &mut code,
            Some(&mut errors),
        )
    };
    let bytes = |blob: &ID3DBlob| {
        // SAFETY: a blob's pointer is valid for its size while it lives.
        unsafe {
            std::slice::from_raw_parts(blob.GetBufferPointer() as *const u8, blob.GetBufferSize())
                .to_vec()
        }
    };
    match (compiled, code) {
        (Ok(()), Some(code)) => Ok(bytes(&code)),
        (result, _) => Err(errors
            .map(|e| String::from_utf8_lossy(&bytes(&e)).trim().to_string())
            .unwrap_or_else(|| format!("{result:?}"))),
    }
}

/// One cursor shape on the GPU.
struct Shape {
    hot_spot: POINT,
    width: u32,
    height: u32,
    blended: ID3D11ShaderResourceView,
    inverted: Option<ID3D11ShaderResourceView>,
}

/// What draws the cursor, and the last shape it drew.
pub(super) struct CursorDrawer {
    vs: ID3D11VertexShader,
    ps: ID3D11PixelShader,
    nearest: ID3D11SamplerState,
    raster: ID3D11RasterizerState,
    over: ID3D11BlendState,
    invert: ID3D11BlendState,
    /// The shape the duplication last handed over; `None` before the first,
    /// or after one that could not be read, and then no cursor is drawn.
    shape: Option<Shape>,
}

impl CursorDrawer {
    pub(super) fn new(device: &ID3D11Device) -> Result<CursorDrawer> {
        let (vs_code, ps_code) = bytecode().ok_or_else(|| Error::from_hresult(E_FAIL))?;
        let mut vs = None;
        let mut ps = None;
        let mut nearest = None;
        let mut raster = None;
        // SAFETY: each description and output lives across its call.
        unsafe {
            device.CreateVertexShader(vs_code, None, Some(&mut vs))?;
            device.CreatePixelShader(ps_code, None, Some(&mut ps))?;
            device.CreateSamplerState(
                &D3D11_SAMPLER_DESC {
                    Filter: D3D11_FILTER_MIN_MAG_MIP_POINT,
                    AddressU: D3D11_TEXTURE_ADDRESS_CLAMP,
                    AddressV: D3D11_TEXTURE_ADDRESS_CLAMP,
                    AddressW: D3D11_TEXTURE_ADDRESS_CLAMP,
                    ComparisonFunc: D3D11_COMPARISON_NEVER,
                    MaxLOD: f32::MAX,
                    ..Default::default()
                },
                Some(&mut nearest),
            )?;
            device.CreateRasterizerState(
                &D3D11_RASTERIZER_DESC {
                    FillMode: D3D11_FILL_SOLID,
                    CullMode: D3D11_CULL_NONE,
                    DepthClipEnable: true.into(),
                    ..Default::default()
                },
                Some(&mut raster),
            )?;
        }
        let made = || Error::from_hresult(E_FAIL);
        Ok(CursorDrawer {
            vs: vs.ok_or_else(made)?,
            ps: ps.ok_or_else(made)?,
            nearest: nearest.ok_or_else(made)?,
            raster: raster.ok_or_else(made)?,
            // Straight alpha over the picture; its own alpha is kept.
            over: blend(device, D3D11_BLEND_SRC_ALPHA, D3D11_BLEND_INV_SRC_ALPHA)?,
            // White turns the picture inside out and black leaves it alone:
            // src × (1 − dst) + dst × (1 − src).
            invert: blend(
                device,
                D3D11_BLEND_INV_DEST_COLOR,
                D3D11_BLEND_INV_SRC_COLOR,
            )?,
            shape: None,
        })
    }

    /// Draw `images` from now, its hot spot at `hot_spot`. One that cannot be
    /// put on the GPU leaves no cursor drawn until the next.
    pub(super) fn set_shape(
        &mut self,
        device: &ID3D11Device,
        images: &ShapeImages,
        hot_spot: POINT,
    ) -> Result<()> {
        self.shape = None;
        self.shape = Some(Shape {
            hot_spot,
            width: images.width,
            height: images.height,
            blended: upload(device, images, &images.blended)?,
            inverted: match &images.inverted {
                Some(inverted) => Some(upload(device, images, inverted)?),
                None => None,
            },
        });
        Ok(())
    }

    /// Forget the shape, after one that could not be read.
    pub(super) fn forget(&mut self) {
        self.shape = None;
    }

    /// The hot spot of the shape drawn; `None` while there is none to draw.
    pub(super) fn hot_spot(&self) -> Option<POINT> {
        self.shape.as_ref().map(|shape| shape.hot_spot)
    }

    /// Draw the shape, its corner at
    /// `corner` in the picture `target` draws into. The caller holds the
    /// device: every state is set here, and the picture and the blend let go again after.
    pub(super) fn draw(
        &self,
        context: &ID3D11DeviceContext,
        target: &ID3D11RenderTargetView,
        corner: (i32, i32),
    ) {
        let Some(shape) = &self.shape else {
            return;
        };
        let viewport = D3D11_VIEWPORT {
            TopLeftX: corner.0 as f32,
            TopLeftY: corner.1 as f32,
            Width: shape.width as f32,
            Height: shape.height as f32,
            MinDepth: 0.0,
            MaxDepth: 1.0,
        };
        // SAFETY: calls on a live context, with objects made on its device.
        unsafe {
            context.OMSetRenderTargets(Some(&[Some(target.clone())]), None);
            context.RSSetViewports(Some(&[viewport]));
            context.RSSetState(&self.raster);
            context.IASetInputLayout(None);
            context.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
            context.VSSetShader(&self.vs, None);
            context.PSSetShader(&self.ps, None);
            context.PSSetSamplers(0, Some(&[Some(self.nearest.clone())]));
            context.OMSetBlendState(&self.over, None, u32::MAX);
            context.PSSetShaderResources(0, Some(&[Some(shape.blended.clone())]));
            context.Draw(4, 0);
            if let Some(inverted) = &shape.inverted {
                context.OMSetBlendState(&self.invert, None, u32::MAX);
                context.PSSetShaderResources(0, Some(&[Some(inverted.clone())]));
                context.Draw(4, 0);
            }
            // The encoder reads the picture next; it must not stay bound here.
            context.PSSetShaderResources(0, Some(&[None]));
            context.OMSetRenderTargets(None, None);
            // The encoder's conversion (`d3d11_nv12.c`) draws on this context
            // without setting either: left inverting, it turned every picture
            // grey once the text cursor had been drawn.
            context.OMSetBlendState(None, None, u32::MAX);
            context.RSSetState(None);
        }
    }
}

/// A blend of the shape's colour by `source` and the picture's by `dest`, the
/// picture's alpha left as it was.
fn blend(
    device: &ID3D11Device,
    source: D3D11_BLEND,
    dest: D3D11_BLEND,
) -> Result<ID3D11BlendState> {
    let mut desc = D3D11_BLEND_DESC::default();
    desc.RenderTarget[0] = D3D11_RENDER_TARGET_BLEND_DESC {
        BlendEnable: true.into(),
        SrcBlend: source,
        DestBlend: dest,
        BlendOp: D3D11_BLEND_OP_ADD,
        SrcBlendAlpha: D3D11_BLEND_ZERO,
        DestBlendAlpha: D3D11_BLEND_ONE,
        BlendOpAlpha: D3D11_BLEND_OP_ADD,
        RenderTargetWriteMask: D3D11_COLOR_WRITE_ENABLE_ALL.0 as u8,
    };
    let mut state = None;
    // SAFETY: `desc` and `state` live across the call.
    unsafe { device.CreateBlendState(&desc, Some(&mut state))? };
    state.ok_or_else(|| Error::from_hresult(E_FAIL))
}

/// One of a shape's pictures as a texture the shaders read.
fn upload(
    device: &ID3D11Device,
    images: &ShapeImages,
    pixels: &[u8],
) -> Result<ID3D11ShaderResourceView> {
    let desc = D3D11_TEXTURE2D_DESC {
        Width: images.width,
        Height: images.height,
        MipLevels: 1,
        ArraySize: 1,
        Format: DXGI_FORMAT_B8G8R8A8_UNORM,
        SampleDesc: DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Usage: D3D11_USAGE_IMMUTABLE,
        BindFlags: D3D11_BIND_SHADER_RESOURCE.0 as u32,
        CPUAccessFlags: 0,
        MiscFlags: 0,
    };
    let data = D3D11_SUBRESOURCE_DATA {
        pSysMem: pixels.as_ptr().cast(),
        SysMemPitch: images.width * 4,
        SysMemSlicePitch: 0,
    };
    let mut texture = None;
    let mut view = None;
    // SAFETY: `pixels` holds the whole texture and outlives the call.
    unsafe {
        device.CreateTexture2D(&desc, Some(&data), Some(&mut texture))?;
        let texture = texture.ok_or_else(|| Error::from_hresult(E_FAIL))?;
        device.CreateShaderResourceView(&texture, None, Some(&mut view))?;
    }
    view.ok_or_else(|| Error::from_hresult(E_FAIL))
}
