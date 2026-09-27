/// Detect the container actually downloaded; never label Opus/WebM as MP3.
({String extension, String mime}) audioContainer(List<int> head) {
  bool at(int offset, List<int> signature) =>
      head.length >= offset + signature.length &&
      List.generate(
        signature.length,
        (i) => head[offset + i] == signature[i],
      ).every((v) => v);
  if (at(4, [0x66, 0x74, 0x79, 0x70]))
    return (extension: 'm4a', mime: 'audio/mp4');
  if (at(0, [0x1a, 0x45, 0xdf, 0xa3]))
    return (extension: 'webm', mime: 'audio/webm');
  if (at(0, [0x4f, 0x67, 0x67, 0x53]))
    return (extension: 'ogg', mime: 'audio/ogg');
  if (at(0, [0x49, 0x44, 0x33]) ||
      head.length > 1 && head[0] == 0xff && (head[1] & 0xe0) == 0xe0) {
    return (extension: 'mp3', mime: 'audio/mpeg');
  }
  throw const FormatException('Unsupported audio container');
}
