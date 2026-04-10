/// The four-character ASCII string `fLaC` that identifies a FLAC stream.
///
/// Every valid FLAC file begins with these four bytes.
const String flacMagic = 'fLaC';

/// First byte of the FLAC magic marker (`0x66`, ASCII `f`).
const int flacMagicByte0 = 0x66;

/// Second byte of the FLAC magic marker (`0x4C`, ASCII `L`).
const int flacMagicByte1 = 0x4C;

/// Third byte of the FLAC magic marker (`0x61`, ASCII `a`).
const int flacMagicByte2 = 0x61;

/// Fourth byte of the FLAC magic marker (`0x43`, ASCII `C`).
const int flacMagicByte3 = 0x43;

/// Size in bytes of a FLAC metadata block header.
///
/// Each metadata block header consists of one byte for flags (is-last + type
/// code) and three bytes for the payload length.
const int flacMetadataHeaderSize = 4;

/// Fixed payload length in bytes of a STREAMINFO metadata block.
///
/// The STREAMINFO block is always exactly 34 bytes, as defined by the FLAC
/// specification.
const int streamInfoPayloadLength = 34;
