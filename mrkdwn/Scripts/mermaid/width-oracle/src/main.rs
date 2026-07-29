//! Emits contiguous Unicode scalar-width runs from the pinned unicode-width
//! crate. Normal and CJK widths provide SwiftMermaid's two ambiguous-width
//! policies. Grapheme clustering remains Swift Character's responsibility.

use std::env;
use std::ffi::OsString;
use std::io::{self, BufWriter, Write};
use unicode_width::UnicodeWidthStr;

fn widths(code_point: u32) -> (u8, u8) {
    match char::from_u32(code_point) {
        None => (1, 1),
        Some(character) => {
            let mut buffer = [0u8; 4];
            let value: &str = character.encode_utf8(&mut buffer);
            (value.width() as u8, value.width_cjk() as u8)
        }
    }
}

fn validate_arguments<I>(mut arguments: I) -> io::Result<()>
where
    I: Iterator<Item = OsString>,
{
    if let Some(argument) = arguments.next() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "swift-mermaid-width-oracle takes no arguments; unexpected argument: {:?}",
                argument
            ),
        ));
    }

    Ok(())
}

fn write_width_runs<W>(output: &mut W) -> io::Result<()>
where
    W: Write,
{
    let mut lower = 0u32;
    let mut current = widths(0);
    for code_point in 1..=0x10FFFFu32 {
        let next = widths(code_point);
        if next != current {
            writeln!(
                output,
                "{:x} {:x} {} {}",
                lower,
                code_point - 1,
                current.0,
                current.1
            )?;
            lower = code_point;
            current = next;
        }
    }
    writeln!(
        output,
        "{:x} {:x} {} {}",
        lower, 0x10FFFFu32, current.0, current.1
    )
}

fn run() -> io::Result<()> {
    validate_arguments(env::args_os().skip(1))?;

    let stdout = io::stdout();
    let mut output = BufWriter::new(stdout.lock());
    write_width_runs(&mut output)?;
    output.flush()
}

fn main() -> io::Result<()> {
    run()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct BrokenPipeWriter;

    impl Write for BrokenPipeWriter {
        fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
            Err(io::Error::new(io::ErrorKind::BrokenPipe, "closed reader"))
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn rejects_unexpected_arguments() {
        let error = validate_arguments([OsString::from("--unexpected")].into_iter()).unwrap_err();

        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn propagates_broken_pipe_without_panicking() {
        let error = write_width_runs(&mut BrokenPipeWriter).unwrap_err();

        assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
    }
}
