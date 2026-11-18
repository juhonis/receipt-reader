// One bounded request per process. No receipt files, logs or network support.
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <io.h>
#include <iostream>
#include <memory>
#include <vector>

namespace {
uint32_t U32(const unsigned char* p) {
  return uint32_t(p[0]) | (uint32_t(p[1]) << 8) |
         (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}
bool Read(char* data, std::streamsize count) {
  return bool(std::cin.read(data, count));
}
}
int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::cout << "receipt-ocr/1 tesseract/" << tesseract::TessBaseAPI::Version() << "\n";
    return 0;
  }
  if (argc != 1) return 2;
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  std::array<unsigned char, 12> header{};
  if (!Read(reinterpret_cast<char*>(header.data()), 12) ||
      std::memcmp(header.data(), "RRO1", 4) != 0) return 2;
  const uint32_t width = U32(header.data() + 4), height = U32(header.data() + 8);
  if (width == 0 || height == 0 || width > 12000 || height > 12000 ||
      uint64_t(width) * height > 24000000) return 2;
  // Composite straight RGBA on white, then supply an 8-bit image to Tesseract.
  std::vector<unsigned char> gray(size_t(width) * height);
  std::vector<unsigned char> line(size_t(width) * 4);
  for (uint32_t y = 0; y < height; ++y) {
    if (!Read(reinterpret_cast<char*>(line.data()), std::streamsize(line.size()))) return 2;
    for (uint32_t x = 0; x < width; ++x) {
      const size_t i = size_t(x) * 4;
      const unsigned int luminance = (299u * line[i] + 587u * line[i+1] + 114u * line[i+2] + 500u) / 1000u;
      gray[size_t(y) * width + x] = static_cast<unsigned char>((luminance * line[i+3] + 255u * (255u - line[i+3]) + 127u) / 255u);
    }
  }
  if (std::cin.get() != std::char_traits<char>::eof()) return 2;
  // Explicit relative data directory; caller sets cwd to this app-owned bundle.
  setMsgSeverity(L_SEVERITY_NONE);
  tesseract::TessBaseAPI api;
  api.SetVariable("debug_file", "NUL");
  if (api.Init("tessdata", "fin+eng", tesseract::OEM_LSTM_ONLY) != 0) return 3;
  api.SetVariable("debug_file", "NUL");
  api.SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
  api.SetImage(gray.data(), static_cast<int>(width), static_cast<int>(height), 1, static_cast<int>(width));
  api.SetSourceResolution(300);
  std::unique_ptr<char[]> result(api.GetTSVText(0));
  if (!result) return 4;
  const size_t size = std::strlen(result.get());
  if (size > 8 * 1024 * 1024) return 4;
  // GetTSVText returns rows only, so supply the stable TSV column header.
  std::cout << "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n";
  std::cout.write(result.get(), static_cast<std::streamsize>(size));
  return std::cout.good() ? 0 : 4;
}
