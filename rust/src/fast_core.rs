//! Keeps a thread off a hybrid processor's efficiency cores. DPDFNet-8 takes
//! 3.6 ms of each 10 ms frame on a performance core of an i7-12700H and 7.9
//! on one of its efficiency cores, where Linux and Windows often put
//! libwebrtc's capture thread, since it sleeps most of the time and looks
//! light (Oct 14). There it fell back to DPDFNet-2 within seconds.
//!
//! The thread is asked onto the fastest cores the first time it runs the
//! model ([`keep_on_fast_cores`]). A processor whose cores are all alike, or
//! one that says nothing about them (a virtual machine), is left alone.

use std::cell::Cell;

/// A core counts as fast when its top clock is at least this share of the
/// fastest core's. Efficiency cores sit far below (3.5 against 4.6 GHz on
/// an i7-12700H, 3.3 against 5.1 on AMD's Zen 5c), while the few cores a
/// processor boosts highest are only a step or two above the rest.
const FAST_SHARE: f64 = 0.85;

thread_local! {
    static ASKED: Cell<bool> = const { Cell::new(false) };
}

/// Moves the calling thread onto the fast cores, once per thread. Never
/// fails: a thread it cannot move runs where it was.
pub(crate) fn keep_on_fast_cores() {
    if ASKED.with(|asked| asked.replace(true)) {
        return;
    }
    platform::keep_on_fast_cores();
}

/// The cores, of `(core, top clock)`, that count as fast, or `None` when
/// that is every one of them and there is nothing to choose.
fn fast_cores(cores: &[(usize, u64)]) -> Option<Vec<usize>> {
    let top = cores.iter().map(|&(_, clock)| clock).max()?;
    let fast: Vec<usize> = cores
        .iter()
        .filter(|&&(_, clock)| clock as f64 >= top as f64 * FAST_SHARE)
        .map(|&(core, _)| core)
        .collect();
    (fast.len() < cores.len()).then_some(fast)
}

#[cfg(target_os = "linux")]
mod platform {
    use std::fs;

    /// glibc's `cpu_set_t`: room for 1024 cores, one bit each.
    #[repr(C)]
    struct CpuSet {
        bits: [u64; 16],
    }

    extern "C" {
        fn sched_getaffinity(pid: i32, size: usize, mask: *mut CpuSet) -> i32;
        fn sched_setaffinity(pid: i32, size: usize, mask: *const CpuSet) -> i32;
    }

    pub(super) fn keep_on_fast_cores() {
        let mut allowed = CpuSet { bits: [0; 16] };
        // SAFETY: `allowed` is a whole cpu_set_t; pid 0 is this thread.
        if unsafe { sched_getaffinity(0, size_of::<CpuSet>(), &mut allowed) } != 0 {
            return;
        }
        // Only among the cores the thread may already use, so a limit the
        // person or a container set still holds.
        let mut cores = Vec::new();
        for core in 0..1024 {
            if allowed.bits[core / 64] & (1 << (core % 64)) == 0 {
                continue;
            }
            let path = format!("/sys/devices/system/cpu/cpu{core}/cpufreq/cpuinfo_max_freq");
            let Some(clock) = fs::read_to_string(path)
                .ok()
                .and_then(|s| s.trim().parse().ok())
            else {
                return;
            };
            cores.push((core, clock));
        }
        let Some(fast) = super::fast_cores(&cores) else {
            return;
        };
        let mut mask = CpuSet { bits: [0; 16] };
        for core in fast {
            mask.bits[core / 64] |= 1 << (core % 64);
        }
        // SAFETY: as above.
        unsafe { sched_setaffinity(0, size_of::<CpuSet>(), &mask) };
    }
}

#[cfg(target_os = "windows")]
mod platform {
    use windows::Win32::System::SystemInformation::{
        CpuSetInformation, GetSystemCpuSetInformation, SYSTEM_CPU_SET_INFORMATION,
    };
    use windows::Win32::System::Threading::{
        GetCurrentProcess, GetCurrentThread, SetThreadSelectedCpuSets,
    };

    /// Windows numbers each kind of core by how capable it is (its
    /// efficiency class: higher is faster), which is the clock the shared
    /// rule above reads. A preference rather than a fence: Windows still
    /// runs the thread elsewhere when every one of these is busy.
    pub(super) fn keep_on_fast_cores() {
        let mut length = 0u32;
        // SAFETY: a null buffer asks only for the length. It fails, as asked
        // with no room, and says the length needed.
        let _ = unsafe {
            GetSystemCpuSetInformation(None, 0, &mut length, Some(GetCurrentProcess()), None)
        };
        if length == 0 {
            return;
        }
        // u64s, so the entries inside are aligned as Windows writes them.
        let mut buffer = vec![0u64; (length as usize).div_ceil(8)];
        // SAFETY: `buffer` holds `length` bytes.
        let filled = unsafe {
            GetSystemCpuSetInformation(
                Some(buffer.as_mut_ptr().cast()),
                length,
                &mut length,
                Some(GetCurrentProcess()),
                None,
            )
        };
        if !filled.as_bool() {
            return;
        }
        let bytes = buffer.as_ptr().cast::<u8>();
        let mut cores = Vec::new();
        let mut at = 0usize;
        while at + size_of::<SYSTEM_CPU_SET_INFORMATION>() <= length as usize {
            // SAFETY: Windows wrote a whole entry here; each says its size.
            let entry = unsafe { &*bytes.add(at).cast::<SYSTEM_CPU_SET_INFORMATION>() };
            if entry.Size == 0 {
                break;
            }
            if entry.Type == CpuSetInformation {
                // SAFETY: the CpuSet member is the one a CpuSetInformation
                // entry carries.
                let set = unsafe { &entry.Anonymous.CpuSet };
                cores.push((set.Id as usize, u64::from(set.EfficiencyClass) + 1));
            }
            at += entry.Size as usize;
        }
        // Classes are 0, 1, ...: with any two, the share rule keeps only the
        // top one, as it should.
        let Some(fast) = super::fast_cores(&cores) else {
            return;
        };
        let ids: Vec<u32> = fast.into_iter().map(|id| id as u32).collect();
        // SAFETY: the pseudo-handle of this thread, and set ids Windows gave.
        // A refusal leaves the thread where it was.
        let _ = unsafe { SetThreadSelectedCpuSets(GetCurrentThread(), &ids) };
    }
}

#[cfg(test)]
mod tests {
    use super::fast_cores;

    #[test]
    fn a_hybrid_processor_keeps_its_performance_cores() {
        // An i7-12700H: twelve threads at 4.6 GHz, eight at 3.5.
        let mut cores: Vec<(usize, u64)> = (0..12).map(|core| (core, 4_600_000)).collect();
        cores.extend((12..20).map(|core| (core, 3_500_000)));
        assert_eq!(fast_cores(&cores), Some((0..12).collect()));
    }

    #[test]
    fn cores_boosted_a_step_higher_do_not_split_the_rest_off() {
        // AMD's preferred cores: a couple 200 MHz above the others.
        let cores = [
            (0, 5_100_000),
            (1, 5_100_000),
            (2, 4_900_000),
            (3, 4_900_000),
        ];
        assert_eq!(fast_cores(&cores), None);
    }

    #[test]
    fn a_processor_of_one_kind_is_left_alone() {
        assert_eq!(fast_cores(&[(0, 3_000_000), (1, 3_000_000)]), None);
        assert_eq!(fast_cores(&[]), None);
    }

    #[test]
    fn windows_efficiency_classes_keep_the_top_one() {
        // Class 1 (performance) and 0 (efficiency), stored one up.
        let cores = [(256, 2), (257, 2), (258, 1), (259, 1)];
        assert_eq!(fast_cores(&cores), Some(vec![256, 257]));
    }
}
