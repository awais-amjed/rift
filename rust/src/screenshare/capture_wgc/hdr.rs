//! An HDR screen's pictures brought down to ordinary colour on the GPU, before
//! anything else sees them.
//!
//! With HDR on, Windows keeps the desktop in 16-bit floating point (scRGB:
//! linear, 1.0 at 80 nits), an ordinary window's white raised to the SDR
//! brightness set in Windows' display settings and a game's highlights above
//! it. Asked for eight bits, Windows hands over a copy it made badly: Windows
//! Graphics Capture cut everything above white off, so a game's sky and lights
//! were blown out, and DXGI's duplication left the SDR brightness out, so a
//! whole screen came out dark (owner's AMD PC and RX 9070 XT, Nov 22 2026).
//!
//! So on an HDR screen the 16-bit picture is asked for and drawn here into an
//! eight-bit one, as OBS draws an HDR source into an SDR canvas: the SDR white
//! Windows was set to becomes white, and what is brighter is rolled off into
//! the top of the range by BT.2390's curve on the brightest channel, from the
//! screen's peak down to that white, instead of cut. The curve is OBS's
//! (`libobs/data/color.effect`, `maxRGB_eetf_linear_to_linear`, GPL-2.0 or
//! later, read Nov 22 2026). OBS's own HDR capture into SDR uses a plain
//! Reinhard curve, which takes white to about half and dims the whole desktop;
//! Sunshine's (`convert_linear_base.hlsl`) clips as Windows does. What comes
//! out is what Rift's capture made on an SDR screen, so the cursor and the
//! encoder's conversion (`d3d11_nv12.c`) go on as they were.

use super::cursor::compile;
use super::dxgi::{self, Copy};
use crate::screenshare::resolution::Size;
use std::sync::{Arc, Mutex};
use windows::core::{s, Error, Interface, Result};
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Win32::Devices::Display::{
    DisplayConfigGetDeviceInfo, GetDisplayConfigBufferSizes, QueryDisplayConfig,
    DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL, DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
    DISPLAYCONFIG_DEVICE_INFO_HEADER, DISPLAYCONFIG_MODE_INFO, DISPLAYCONFIG_PATH_INFO,
    DISPLAYCONFIG_SDR_WHITE_LEVEL, DISPLAYCONFIG_SOURCE_DEVICE_NAME, QDC_ONLY_ACTIVE_PATHS,
};
use windows::Win32::Foundation::{ERROR_SUCCESS, E_FAIL, HWND};
use windows::Win32::Graphics::Direct3D::D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP;
use windows::Win32::Graphics::Direct3D10::ID3D10Multithread;
use windows::Win32::Graphics::Direct3D11::{
    ID3D11Buffer, ID3D11Device, ID3D11DeviceContext, ID3D11PixelShader, ID3D11RenderTargetView,
    ID3D11Texture2D, ID3D11VertexShader, D3D11_BIND_CONSTANT_BUFFER, D3D11_BUFFER_DESC,
    D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT, D3D11_VIEWPORT,
};
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020, DXGI_FORMAT_R16G16B16A16_FLOAT,
};
use windows::Win32::Graphics::Dxgi::{CreateDXGIFactory1, IDXGIFactory1, IDXGIOutput6};
use windows::Win32::Graphics::Gdi::{
    GetMonitorInfoW, MonitorFromWindow, HMONITOR, MONITORINFO, MONITORINFOEXW,
    MONITOR_DEFAULTTONEAREST,
};

/// The format an HDR screen's pictures come in.
pub(super) const HDR_FORMAT: windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT =
    DXGI_FORMAT_R16G16B16A16_FLOAT;

/// A white of 80 nits, scRGB's 1.0 and Windows' SDR brightness at the slider's
/// bottom: what Windows' own eight-bit copy is, for a screen whose setting
/// cannot be read.
const UNREAD_WHITE: f32 = 80.0;

/// The peak taken for a screen that reports none, or one no brighter than its
/// white: the brightness HDR games are mostly made for.
const UNREPORTED_PEAK: f32 = 1000.0;

/// How bright an HDR screen's white and its peak are, in nits.
#[derive(Clone, Copy, PartialEq, Debug)]
pub(super) struct Light {
    pub(super) white: f32,
    pub(super) peak: f32,
}

impl Light {
    /// A screen whose light could not be read: white where Windows' own
    /// eight-bit copy puts it.
    pub(super) fn unread() -> Light {
        Light::new(None, None)
    }

    /// From Windows' SDR white level (1000 for 80 nits) and the screen's
    /// reported peak, either missing.
    fn new(white_level: Option<u32>, reported_peak: Option<f32>) -> Light {
        let white = white_level
            .filter(|&level| level > 0)
            .map_or(UNREAD_WHITE, |level| level as f32 * 80.0 / 1000.0);
        let peak = reported_peak
            .filter(|peak| peak.is_finite() && *peak > white && *peak <= 10_000.0)
            .unwrap_or(UNREPORTED_PEAK.max(white));
        Light { white, peak }
    }
}

/// The light of `monitor` while it shows HDR; `None` for an SDR screen, whose
/// pictures need nothing done.
pub(super) fn light_of(monitor: HMONITOR) -> Option<Light> {
    let peak = hdr_peak(monitor)?;
    let white = sdr_white_level(monitor);
    if white.is_none() {
        log::warn!("capture: the HDR screen's SDR brightness could not be read");
    }
    Some(Light::new(white, peak))
}

/// The monitor a window shows on, most of it.
pub(super) fn monitor_of_window(id: u64) -> HMONITOR {
    // SAFETY: a closed window gives the nearest monitor, or none.
    unsafe { MonitorFromWindow(HWND(id as isize as *mut _), MONITOR_DEFAULTTONEAREST) }
}

/// `Some` with the reported peak, itself perhaps missing, when `monitor` is in
/// HDR; `None` when it is not, or cannot be found among the outputs.
fn hdr_peak(monitor: HMONITOR) -> Option<Option<f32>> {
    // SAFETY: plain DXGI calls with no pointers kept. A new factory each time:
    // an old one's outputs keep the colour space they had when it was made.
    unsafe {
        let factory: IDXGIFactory1 = CreateDXGIFactory1().ok()?;
        let outputs = (0..)
            .map_while(|at| factory.EnumAdapters1(at).ok())
            .flat_map(|adapter| (0..).map_while(move |at| adapter.EnumOutputs(at).ok()));
        for output in outputs {
            let Ok(desc) = output.cast::<IDXGIOutput6>().and_then(|o| o.GetDesc1()) else {
                continue;
            };
            if desc.Monitor == monitor {
                return (desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020)
                    .then_some((desc.MaxLuminance > 0.0).then_some(desc.MaxLuminance));
            }
        }
    }
    None
}

/// Windows' SDR white level for `monitor` (1000 is 80 nits), found by its GDI
/// name among the active display paths.
fn sdr_white_level(monitor: HMONITOR) -> Option<u32> {
    let mut info = MONITORINFOEXW {
        monitorInfo: MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFOEXW>() as u32,
            ..Default::default()
        },
        ..Default::default()
    };
    // SAFETY: `info` is the size it says; every buffer below is sized by the
    // call before and lives across the calls that write it.
    unsafe {
        if !GetMonitorInfoW(monitor, &mut info.monitorInfo).as_bool() {
            return None;
        }
        let (mut path_count, mut mode_count) = (0u32, 0u32);
        if GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut path_count, &mut mode_count)
            != ERROR_SUCCESS
        {
            return None;
        }
        let mut paths = vec![DISPLAYCONFIG_PATH_INFO::default(); path_count as usize];
        let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); mode_count as usize];
        if QueryDisplayConfig(
            QDC_ONLY_ACTIVE_PATHS,
            &mut path_count,
            paths.as_mut_ptr(),
            &mut mode_count,
            modes.as_mut_ptr(),
            None,
        ) != ERROR_SUCCESS
        {
            return None;
        }
        paths.truncate(path_count as usize);
        for path in &paths {
            let mut source = DISPLAYCONFIG_SOURCE_DEVICE_NAME {
                header: DISPLAYCONFIG_DEVICE_INFO_HEADER {
                    r#type: DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
                    size: std::mem::size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32,
                    adapterId: path.sourceInfo.adapterId,
                    id: path.sourceInfo.id,
                },
                ..Default::default()
            };
            if DisplayConfigGetDeviceInfo(&mut source.header) != 0
                || source.viewGdiDeviceName != info.szDevice
            {
                continue;
            }
            let mut white = DISPLAYCONFIG_SDR_WHITE_LEVEL {
                header: DISPLAYCONFIG_DEVICE_INFO_HEADER {
                    r#type: DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL,
                    size: std::mem::size_of::<DISPLAYCONFIG_SDR_WHITE_LEVEL>() as u32,
                    adapterId: path.targetInfo.adapterId,
                    id: path.targetInfo.id,
                },
                SDRWhiteLevel: 0,
            };
            return (DisplayConfigGetDeviceInfo(&mut white.header) == 0)
                .then_some(white.SDRWhiteLevel);
        }
    }
    None
}

/// A quad over the viewport, each pixel of the 16-bit picture read as it is
/// and written in eight-bit sRGB. The curve below is OBS's (see the module).
const SHADERS: &str = r"
cbuffer Light : register(b0) { float white; float peak; float2 unused; };
Texture2D<float4> picture : register(t0);
struct Corner { float4 at : SV_Position; };
Corner vs(uint id : SV_VertexID) {
    Corner c;
    c.at = float4((id & 1) ? 1.0 : -1.0, (id & 2) ? -1.0 : 1.0, 0.0, 1.0);
    return c;
}
float to_pq(float x) {
    float c = pow(abs(x), 0.1593017578);
    return pow((0.8359375 + 18.8515625 * c) / (1.0 + 18.6875 * c), 78.84375);
}
float from_pq(float u) {
    float c = pow(abs(u), 1.0 / 78.84375);
    return pow(abs(max(c - 0.8359375, 0.0) / (18.8515625 - 18.6875 * c)), 1.0 / 0.1593017578);
}
float eetf(float e_pq, float lw, float lmax) {
    float lw_pq = to_pq(lw / 10000.0);
    float e1 = saturate(e_pq / lw_pq);
    float max_lum = to_pq(lmax / 10000.0) / lw_pq;
    float ks = 1.5 * max_lum - 0.5;
    float e2 = e1;
    if (e1 > ks) {
        float t = (e1 - ks) / (1.0 - ks);
        float t2 = t * t;
        float t3 = t2 * t;
        e2 = (2.0 * t3 - 3.0 * t2 + 1.0) * ks + (t3 - 2.0 * t2 + t) * (1.0 - ks)
            + (-2.0 * t3 + 3.0 * t2) * max_lum;
    }
    return e2 * lw_pq;
}
float srgb(float u) {
    return (u <= 0.0031308) ? (12.92 * u) : (1.055 * pow(u, 1.0 / 2.4) - 0.055);
}
float4 ps(Corner c) : SV_Target {
    float3 rgb = max(picture.Load(int3(c.at.xy, 0)).rgb, 0.0) * (80.0 / 10000.0);
    if (peak > white) {
        float m = max(max(rgb.r, rgb.g), rgb.b);
        rgb *= from_pq(eetf(to_pq(m), peak, white)) / max(m, 6.10352e-5);
    }
    rgb = saturate(rgb * (10000.0 / white));
    return float4(srgb(rgb.r), srgb(rgb.g), srgb(rgb.b), 1.0);
}
";

/// The two shaders' bytecode, compiled once a process.
fn bytecode() -> Option<&'static (Vec<u8>, Vec<u8>)> {
    static CODE: std::sync::OnceLock<Option<(Vec<u8>, Vec<u8>)>> = std::sync::OnceLock::new();
    CODE.get_or_init(|| {
        match (
            compile(SHADERS, s!("vs"), s!("vs_4_0")),
            compile(SHADERS, s!("ps"), s!("ps_4_0")),
        ) {
            (Ok(vs), Ok(ps)) => Some((vs, ps)),
            (Err(e), _) | (_, Err(e)) => {
                log::warn!("capture: the HDR shaders did not compile: {e}");
                None
            }
        }
    })
    .as_ref()
}

/// What draws a 16-bit picture into an eight-bit one.
pub(super) struct ToSdr {
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    /// Held across a draw, whose states and draws must not mix with the
    /// encoder's commands on the device.
    lock: ID3D10Multithread,
    vs: ID3D11VertexShader,
    ps: ID3D11PixelShader,
    light: ID3D11Buffer,
}

// SAFETY: a multithread-protected device; every draw holds its lock.
unsafe impl Send for ToSdr {}
unsafe impl Sync for ToSdr {}

impl ToSdr {
    pub(super) fn new(device: &ID3D11Device) -> Result<ToSdr> {
        let (vs_code, ps_code) = bytecode().ok_or_else(|| Error::from_hresult(E_FAIL))?;
        let mut vs = None;
        let mut ps = None;
        let mut light = None;
        // SAFETY: each description and output lives across its call.
        let context = unsafe {
            device.CreateVertexShader(vs_code, None, Some(&mut vs))?;
            device.CreatePixelShader(ps_code, None, Some(&mut ps))?;
            device.CreateBuffer(
                &D3D11_BUFFER_DESC {
                    ByteWidth: 16,
                    Usage: D3D11_USAGE_DEFAULT,
                    BindFlags: D3D11_BIND_CONSTANT_BUFFER.0 as u32,
                    ..Default::default()
                },
                None,
                Some(&mut light),
            )?;
            device.GetImmediateContext()?
        };
        let made = || Error::from_hresult(E_FAIL);
        Ok(ToSdr {
            device: device.clone(),
            context,
            lock: device.cast()?,
            vs: vs.ok_or_else(made)?,
            ps: ps.ok_or_else(made)?,
            light: light.ok_or_else(made)?,
        })
    }

    /// Draw `source`, a 16-bit texture that can be read by a shader, into
    /// `target` pixel for pixel, `size` of it, in `light`. Nothing waits for
    /// the GPU: the encoder reads `target` later on the same device's queue.
    pub(super) fn draw(
        &self,
        source: &ID3D11Texture2D,
        target: &ID3D11RenderTargetView,
        size: Size,
        light: Light,
    ) -> Result<()> {
        let mut view = None;
        // SAFETY: a texture on this device, made to be read by a shader.
        unsafe {
            self.device
                .CreateShaderResourceView(source, None, Some(&mut view))?
        };
        let view = view.ok_or_else(|| Error::from_hresult(E_FAIL))?;
        let constants = [light.white, light.peak, 0.0, 0.0];
        let viewport = D3D11_VIEWPORT {
            TopLeftX: 0.0,
            TopLeftY: 0.0,
            Width: size.width as f32,
            Height: size.height as f32,
            MinDepth: 0.0,
            MaxDepth: 1.0,
        };
        let c = &self.context;
        // SAFETY: calls on a live context, with objects made on its device,
        // the device held across them; `constants` outlives its upload.
        unsafe {
            self.lock.Enter();
            c.UpdateSubresource(&self.light, 0, None, constants.as_ptr().cast(), 0, 0);
            c.OMSetRenderTargets(Some(&[Some(target.clone())]), None);
            c.RSSetViewports(Some(&[viewport]));
            c.RSSetState(None);
            c.OMSetBlendState(None, None, u32::MAX);
            c.IASetInputLayout(None);
            c.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
            c.VSSetShader(&self.vs, None);
            c.PSSetShader(&self.ps, None);
            c.PSSetConstantBuffers(0, Some(&[Some(self.light.clone())]));
            c.PSSetShaderResources(0, Some(&[Some(view)]));
            c.Draw(4, 0);
            // The encoder reads the picture next; neither may stay bound.
            c.PSSetShaderResources(0, Some(&[None]));
            c.OMSetRenderTargets(None, None);
            self.lock.Leave();
        }
        Ok(())
    }
}

/// A Windows Graphics Capture session's side of it: whether its screen is in
/// HDR, so the frame pool asks for 16 bits, and the eight-bit copies each such
/// picture is drawn into on the frame pool's thread.
pub(super) struct WgcHdr {
    device: ID3D11Device,
    light: Mutex<Option<Light>>,
    /// Made at the first 16-bit picture, at its size; `Err` once that failed,
    /// and the pool then goes back to eight bits.
    drawing: Mutex<Option<std::result::Result<Drawing, ()>>>,
}

struct Drawing {
    to_sdr: ToSdr,
    size: Size,
    copies: Vec<Arc<Copy>>,
}

impl WgcHdr {
    pub(super) fn new(device: ID3D11Device, light: Option<Light>) -> WgcHdr {
        WgcHdr {
            device,
            light: Mutex::new(light),
            drawing: Mutex::new(None),
        }
    }

    /// The screen's light now, read again by the share every few seconds: a
    /// window moved to another screen, HDR turned on or off, or the SDR
    /// brightness moved. It takes the pool to the other format if it must.
    pub(super) fn set_light(&self, light: Option<Light>) {
        let mut known = self.light.lock().unwrap();
        if *known != light {
            log_light(light);
            *known = light;
        }
    }

    /// The format the frame pool should be in.
    pub(super) fn format(&self) -> DirectXPixelFormat {
        let failed = matches!(*self.drawing.lock().unwrap(), Some(Err(())));
        if self.light.lock().unwrap().is_some() && !failed {
            DirectXPixelFormat::R16G16B16A16Float
        } else {
            DirectXPixelFormat::B8G8R8A8UIntNormalized
        }
    }

    /// `texture`, a 16-bit picture of `desc`, in a free eight-bit copy. `None`
    /// while every copy is out, or after drawing failed.
    pub(super) fn bring_down(
        &self,
        texture: &ID3D11Texture2D,
        desc: &D3D11_TEXTURE2D_DESC,
    ) -> Option<Arc<Copy>> {
        // A screen read as SDR while its pictures still come in 16 bits, until
        // the pool takes the new format.
        let light = self.light.lock().unwrap().unwrap_or_else(Light::unread);
        let size = Size {
            width: desc.Width,
            height: desc.Height,
        };
        let mut drawing = self.drawing.lock().unwrap();
        if !matches!(&*drawing, Some(Ok(d)) if d.size == size) {
            if matches!(*drawing, Some(Err(()))) {
                return None;
            }
            *drawing = Some(
                ToSdr::new(&self.device)
                    .and_then(|to_sdr| {
                        Ok(Drawing {
                            copies: dxgi::copies(&self.device, size)?,
                            to_sdr,
                            size,
                        })
                    })
                    .map_err(|e| log::warn!("capture: HDR pictures cannot be drawn: {e}")),
            );
        }
        let Some(Ok(drawing)) = &*drawing else {
            return None;
        };
        let copy = dxgi::free(&drawing.copies)?;
        if let Err(e) = drawing.to_sdr.draw(texture, copy.view(), size, light) {
            log::warn!("capture: an HDR picture was not drawn: {e}");
            return None;
        }
        Some(copy)
    }
}

/// Says in the log what a share's screen is now.
pub(super) fn log_light(light: Option<Light>) {
    match light {
        Some(light) => log::info!(
            "capture: an HDR screen, white at {:.0} nits and peak {:.0}; brought down to SDR",
            light.white,
            light.peak
        ),
        None => log::info!("capture: an SDR screen"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_white_level_is_read_as_nits() {
        assert_eq!(Light::new(Some(1000), Some(1000.0)).white, 80.0);
        assert_eq!(Light::new(Some(3000), Some(1000.0)).white, 240.0);
    }

    #[test]
    fn an_unread_white_is_windows_own_and_a_missing_peak_a_thousand_nits() {
        assert_eq!(
            Light::new(None, None),
            Light {
                white: 80.0,
                peak: 1000.0
            }
        );
        assert_eq!(Light::new(Some(0), Some(0.0)).white, 80.0);
    }

    #[test]
    fn a_peak_no_brighter_than_white_is_not_believed() {
        // A screen reporting 200 nits with white set to 240.
        assert_eq!(Light::new(Some(3000), Some(200.0)).peak, 1000.0);
        assert_eq!(Light::new(Some(3000), Some(f32::NAN)).peak, 1000.0);
        // White set above a thousand: nothing to roll off.
        assert_eq!(Light::new(Some(15_000), None).peak, 1200.0);
    }

    /// The shader on a real GPU: each pixel of a row of scRGB values, in
    /// nits, drawn into eight bits and read back as BGRA.
    fn drawn(light: Light, nits: &[[f32; 3]]) -> Vec<[u8; 4]> {
        use windows::Win32::Foundation::HMODULE;
        use windows::Win32::Graphics::Direct3D::D3D_DRIVER_TYPE_HARDWARE;
        use windows::Win32::Graphics::Direct3D11::{
            D3D11CreateDevice, D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE,
            D3D11_CPU_ACCESS_READ, D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_MAPPED_SUBRESOURCE,
            D3D11_MAP_READ, D3D11_SDK_VERSION, D3D11_SUBRESOURCE_DATA, D3D11_USAGE_STAGING,
        };
        use windows::Win32::Graphics::Dxgi::Common::{
            DXGI_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_R32G32B32A32_FLOAT,
            DXGI_SAMPLE_DESC,
        };
        let width = nits.len() as u32;
        let desc = |format: DXGI_FORMAT, bind: u32| D3D11_TEXTURE2D_DESC {
            Width: width,
            Height: 1,
            MipLevels: 1,
            ArraySize: 1,
            Format: format,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: bind,
            ..Default::default()
        };
        // scRGB: 1.0 is 80 nits. 32-bit floats here; the shader reads 16
        // the same way.
        let pixels: Vec<f32> = nits
            .iter()
            .flat_map(|[r, g, b]| [r / 80.0, g / 80.0, b / 80.0, 1.0])
            .collect();
        let mut device = None;
        let mut source = None;
        let mut target = None;
        let mut staging = None;
        let mut view = None;
        // SAFETY: plain D3D11 calls, every buffer living across its call.
        unsafe {
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                None,
            )
            .unwrap();
            let device: ID3D11Device = device.unwrap();
            device
                .CreateTexture2D(
                    &desc(
                        DXGI_FORMAT_R32G32B32A32_FLOAT,
                        D3D11_BIND_SHADER_RESOURCE.0 as u32,
                    ),
                    Some(&D3D11_SUBRESOURCE_DATA {
                        pSysMem: pixels.as_ptr().cast(),
                        SysMemPitch: width * 16,
                        SysMemSlicePitch: 0,
                    }),
                    Some(&mut source),
                )
                .unwrap();
            device
                .CreateTexture2D(
                    &desc(
                        DXGI_FORMAT_B8G8R8A8_UNORM,
                        D3D11_BIND_RENDER_TARGET.0 as u32,
                    ),
                    None,
                    Some(&mut target),
                )
                .unwrap();
            let target = target.unwrap();
            device
                .CreateRenderTargetView(&target, None, Some(&mut view))
                .unwrap();
            let mut read = desc(DXGI_FORMAT_B8G8R8A8_UNORM, 0);
            read.Usage = D3D11_USAGE_STAGING;
            read.CPUAccessFlags = D3D11_CPU_ACCESS_READ.0 as u32;
            device
                .CreateTexture2D(&read, None, Some(&mut staging))
                .unwrap();
            let staging = staging.unwrap();

            ToSdr::new(&device)
                .unwrap()
                .draw(
                    &source.unwrap(),
                    &view.unwrap(),
                    Size { width, height: 1 },
                    light,
                )
                .unwrap();
            let context = device.GetImmediateContext().unwrap();
            context.CopyResource(&staging, &target);
            let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
            context
                .Map(&staging, 0, D3D11_MAP_READ, 0, Some(&mut mapped))
                .unwrap();
            let bytes = std::slice::from_raw_parts(mapped.pData as *const u8, width as usize * 4);
            let out = bytes.chunks(4).map(|p| [p[0], p[1], p[2], p[3]]).collect();
            context.Unmap(&staging, 0);
            out
        }
    }

    #[test]
    #[ignore = "needs a GPU"]
    fn live_hdr_pictures_come_down_to_sdr_white_and_roll_off_above_it() {
        let light = Light {
            white: 240.0,
            peak: 1000.0,
        };
        let grey = |nits: f32| [nits, nits, nits];
        let out = drawn(
            light,
            &[
                grey(0.0),
                grey(24.0),
                grey(240.0),
                grey(480.0),
                grey(1000.0),
                grey(4000.0),
                [960.0, 0.0, 0.0],
                [-5.0, 120.0, 0.0],
            ],
        );
        eprintln!("drawn: {out:?}");
        let level = |at: usize| out[at][2];
        assert_eq!(out[0], [0, 0, 0, 255], "black stays black");
        // A tenth of white, below the curve's knee, as on an SDR screen:
        // sRGB of 0.1 is 0.349.
        assert!(
            (88..=90).contains(&level(1)),
            "dark grey kept: {}",
            level(1)
        );
        // White rolled off a little to leave room above it.
        assert!(
            (215..=250).contains(&level(2)),
            "white near white: {}",
            level(2)
        );
        assert!(
            level(3) > level(2) && level(3) < 255,
            "twice white still brighter"
        );
        assert!(level(4) > level(3), "the peak brighter again");
        assert_eq!(level(4), 255, "the peak is white");
        assert_eq!(level(5), 255, "past the peak, white");
        for pixel in &out[..6] {
            assert!(
                pixel[0] == pixel[1] && pixel[1] == pixel[2],
                "grey stays grey"
            );
        }
        // A bright red keeps its hue: its other channels stay dark.
        assert!(
            out[6][2] > 200 && out[6][1] == 0 && out[6][0] == 0,
            "red: {:?}",
            out[6]
        );
        // Out of sRGB's gamut, below zero: clipped, not wrapped.
        assert_eq!(out[7][2], 0);
    }

    #[test]
    #[ignore = "needs a GPU"]
    fn live_hdr_with_no_room_above_white_is_cut_at_white() {
        let out = drawn(
            Light {
                white: 240.0,
                peak: 240.0,
            },
            &[[24.0; 3], [240.0; 3], [480.0; 3]],
        );
        eprintln!("drawn: {out:?}");
        assert!((88..=90).contains(&out[0][2]));
        assert_eq!(out[1][2], 255);
        assert_eq!(out[2][2], 255);
    }
}
