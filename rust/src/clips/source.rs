//! The file a chat video plays from, read where the player wants it.
//!
//! A big video is not handed over whole: the app fetches and opens it a
//! chunk at a time as it plays (`ChunkedBlobReader`), and the player reads it
//! through a [`Source`]. A read the source does not hold asks the app for a
//! block from there (`ClipRead`, on `clip_read_stream`) and waits on the
//! player's own thread until the app answers (`clip_answer`). The last few
//! blocks stay, so a demuxer reading a sample at a time crosses to the app
//! once a block, not once a sample.
//!
//! A small video, and a poster's, is read the same way, from the whole file
//! the app holds; tests read one in memory ([`Source::memory`]).
use crate::api::clips::ClipRead;
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Condvar, Mutex};

/// What one ask fetches.
const BLOCK: u64 = 512 * 1024;
/// Blocks kept after they are read.
const KEPT: usize = 6;

/// Why a read has no bytes.
#[derive(Debug)]
pub(crate) enum ReadError {
    /// The clip is closing; the player is being stopped.
    Closed,
    /// The app could not fetch or open them.
    Failed(String),
}

/// A run of a block, lent to the player without a copy.
pub(crate) struct Span {
    block: Arc<Vec<u8>>,
    from: usize,
    to: usize,
}

impl Span {
    pub(crate) fn len(&self) -> usize {
        self.to - self.from
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.to == self.from
    }
}

impl AsRef<[u8]> for Span {
    fn as_ref(&self) -> &[u8] {
        &self.block[self.from..self.to]
    }
}

type Ask = Box<dyn Fn(ClipRead) + Send + Sync>;

pub(crate) struct Source {
    texture: u64,
    length: u64,
    /// None for one in memory, which never asks.
    ask: Option<Ask>,
    state: Mutex<State>,
    answered: Condvar,
}

#[derive(Default)]
struct State {
    /// Where each block starts, and it; the last read at the back.
    blocks: VecDeque<(u64, Arc<Vec<u8>>)>,
    next_request: u64,
    answers: HashMap<u64, Result<Vec<u8>, String>>,
    closed: bool,
}

impl Source {
    /// A file in memory, for tests.
    #[cfg(test)]
    pub(crate) fn memory(bytes: Vec<u8>) -> Arc<Source> {
        let length = bytes.len() as u64;
        let state = State {
            blocks: VecDeque::from([(0, Arc::new(bytes))]),
            ..State::default()
        };
        Arc::new(Source {
            texture: 0,
            length,
            ask: None,
            state: Mutex::new(state),
            answered: Condvar::new(),
        })
    }

    /// [length] bytes the app hands over as asked, through [ask], for the
    /// clip in [texture].
    pub(crate) fn pulled(texture: u64, length: u64, ask: Ask) -> Arc<Source> {
        Arc::new(Source {
            texture,
            length,
            ask: Some(ask),
            state: Mutex::new(State::default()),
            answered: Condvar::new(),
        })
    }

    pub(crate) fn len(&self) -> u64 {
        self.length
    }

    /// Up to [max] bytes from [offset] on: fewer where a block ends, none at
    /// the end. Waits for the app when they are not here.
    pub(crate) fn read_at(&self, offset: u64, max: usize) -> Result<Span, ReadError> {
        let empty = || Span {
            block: Arc::new(Vec::new()),
            from: 0,
            to: 0,
        };
        if offset >= self.length || max == 0 {
            return Ok(empty());
        }
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        loop {
            if state.closed {
                return Err(ReadError::Closed);
            }
            if let Some(span) = state.find(offset, max) {
                return Ok(span);
            }
            let Some(ask) = &self.ask else {
                return Err(ReadError::Failed("Past the end of the file".into()));
            };
            let request = state.next_request;
            state.next_request += 1;
            let length = BLOCK.min(self.length - offset) as u32;
            drop(state);
            ask(ClipRead {
                texture: self.texture,
                request,
                offset,
                length,
            });
            state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            while !state.closed && !state.answers.contains_key(&request) {
                state = self
                    .answered
                    .wait(state)
                    .unwrap_or_else(|e| e.into_inner());
            }
            match state.answers.remove(&request) {
                None => return Err(ReadError::Closed),
                Some(Err(e)) => return Err(ReadError::Failed(e)),
                Some(Ok(bytes)) if bytes.is_empty() => {
                    return Err(ReadError::Failed("The file ended early".into()))
                }
                Some(Ok(bytes)) => {
                    state.blocks.push_back((offset, Arc::new(bytes)));
                    while state.blocks.len() > KEPT {
                        state.blocks.pop_front();
                    }
                }
            }
        }
    }

    /// The app's answer to [request]: the bytes, or why there are none.
    pub(crate) fn answer(&self, request: u64, bytes: Result<Vec<u8>, String>) {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if !state.closed {
            state.answers.insert(request, bytes);
        }
        self.answered.notify_all();
    }

    /// Wakes every read waiting on the app, and refuses those after: what
    /// is stopping the player waits for its threads, which may be waiting
    /// here.
    pub(crate) fn close(&self) {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        state.closed = true;
        state.answers.clear();
        self.answered.notify_all();
    }
}

impl State {
    fn find(&mut self, offset: u64, max: usize) -> Option<Span> {
        let at = self
            .blocks
            .iter()
            .position(|(start, block)| *start <= offset && offset < start + block.len() as u64)?;
        let (start, block) = self.blocks.remove(at)?;
        let from = (offset - start) as usize;
        let to = block.len().min(from + max);
        let span = Span {
            block: block.clone(),
            from,
            to,
        };
        self.blocks.push_back((start, block));
        Some(span)
    }
}

// ── The open clips' sources, for the app's answers ──────────────────────────

static PULLED: Mutex<Option<HashMap<u64, Arc<Source>>>> = Mutex::new(None);

/// Makes [source] the one the app's answers for [texture] go to.
pub(crate) fn register(texture: u64, source: Arc<Source>) {
    let mut pulled = PULLED.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(old) = pulled.get_or_insert_with(HashMap::new).insert(texture, source) {
        old.close();
    }
}

/// Closes [texture]'s source, waking its reads, and forgets it.
pub(crate) fn unregister(texture: u64) {
    let source = PULLED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_mut()
        .and_then(|p| p.remove(&texture));
    if let Some(source) = source {
        source.close();
    }
}

/// Closes [texture]'s source without forgetting it: its player is about to
/// be stopped, and must not wait on the app meanwhile.
pub(crate) fn close(texture: u64) {
    let source = PULLED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|p| p.get(&texture).cloned());
    if let Some(source) = source {
        source.close();
    }
}

/// The app's answer to [texture]'s [request]; dropped when the clip has gone.
pub(crate) fn answer(texture: u64, request: u64, bytes: Result<Vec<u8>, String>) {
    let source = PULLED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|p| p.get(&texture).cloned());
    if let Some(source) = source {
        source.answer(request, bytes);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;

    fn file(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8).collect()
    }

    /// A source whose asks are answered from [whole] by a thread standing
    /// in for the app, which counts them.
    fn answered(whole: Vec<u8>) -> (Arc<Source>, Arc<Mutex<Vec<ClipRead>>>) {
        let asked = Arc::new(Mutex::new(Vec::new()));
        let (tx, rx) = mpsc::channel::<ClipRead>();
        let source = Source::pulled(
            7,
            whole.len() as u64,
            Box::new(move |read| {
                let _ = tx.send(read);
            }),
        );
        let answering = source.clone();
        let log = asked.clone();
        thread::spawn(move || {
            for read in rx {
                let from = read.offset as usize;
                let to = whole.len().min(from + read.length as usize);
                answering.answer(read.request, Ok(whole[from..to].to_vec()));
                log.lock().unwrap().push(read);
            }
        });
        (source, asked)
    }

    #[test]
    fn memory_reads_where_asked() {
        let source = Source::memory(file(100));
        let span = source.read_at(10, 5).unwrap();
        assert_eq!(span.as_ref(), &file(100)[10..15]);
        assert!(source.read_at(100, 5).unwrap().is_empty());
    }

    #[test]
    fn small_reads_ask_once_a_block() {
        let whole = file(3 * BLOCK as usize + 100);
        let (source, asked) = answered(whole.clone());
        let mut at = 0u64;
        let mut got = Vec::new();
        while at < source.len() {
            let span = source.read_at(at, 4096).unwrap();
            assert!(!span.is_empty());
            got.extend_from_slice(span.as_ref());
            at += span.len() as u64;
        }
        assert_eq!(got, whole);
        assert_eq!(asked.lock().unwrap().len(), 4);
        // Read again: still held.
        source.read_at(0, 10).unwrap();
        assert_eq!(asked.lock().unwrap().len(), 4);
    }

    #[test]
    fn a_failed_answer_fails_the_read() {
        let source = Source::pulled(1, 1000, Box::new(|_| {}));
        let reading = {
            let source = source.clone();
            thread::spawn(move || source.read_at(0, 10).map(|s| s.len()))
        };
        thread::sleep(std::time::Duration::from_millis(50));
        source.answer(0, Err("no network".into()));
        assert!(matches!(reading.join().unwrap(), Err(ReadError::Failed(_))));
    }

    #[test]
    fn closing_wakes_a_waiting_read() {
        let source = Source::pulled(1, 1000, Box::new(|_| {}));
        let reading = {
            let source = source.clone();
            thread::spawn(move || source.read_at(0, 10).map(|s| s.len()))
        };
        thread::sleep(std::time::Duration::from_millis(50));
        source.close();
        assert!(matches!(reading.join().unwrap(), Err(ReadError::Closed)));
        assert!(matches!(source.read_at(0, 10), Err(ReadError::Closed)));
    }
}
