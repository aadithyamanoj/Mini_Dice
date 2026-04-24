#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr std::uint32_t kMetaWordBytes = 256;
constexpr std::uint32_t kFetchBeatBytes = 2;

struct ExpectedWrite {
  std::uint32_t addr;
  std::uint32_t data;
  std::uint32_t strb;
};

std::string g_cta_hex;
std::unordered_map<std::uint32_t, std::string> g_meta_words;
std::unordered_map<std::uint32_t, std::string> g_bitstream_words;
std::uint32_t g_csr_values[8] = {};
std::vector<ExpectedWrite> g_expected_writes;
std::size_t g_observed_write_idx = 0;
std::uint32_t g_error_count = 0;
std::string g_init_error;

bool file_exists(const std::string& path) {
  std::ifstream stream(path);
  return static_cast<bool>(stream);
}

bool has_path_component(const std::string& path) {
  return !path.empty() &&
         (path.front() == '/' || path.find('/') != std::string::npos);
}

std::string join_path(const std::string& base, const std::string& leaf) {
  if (base.empty()) {
    return leaf;
  }
  if (base.back() == '/') {
    return base + leaf;
  }
  return base + "/" + leaf;
}

std::string repo_root_from_source_path() {
  const std::string source_path(__FILE__);
  const std::string suffix = "/tb/cgra_core/dice_core/dpi_dice_core_runtime.cpp";
  const std::size_t suffix_pos = source_path.rfind(suffix);
  if (suffix_pos == std::string::npos) {
    return "";
  }
  return source_path.substr(0, suffix_pos);
}

std::string resolve_input_path(const std::string& path) {
  if (file_exists(path)) {
    return path;
  }

  if (path.empty()) {
    return path;
  }

  std::vector<std::string> search_roots;
  if (const char* dice_home_env = std::getenv("DICE_HOME")) {
    search_roots.emplace_back(dice_home_env);
  }

  const std::string source_repo_root = repo_root_from_source_path();
  if (!source_repo_root.empty() &&
      std::find(search_roots.begin(), search_roots.end(), source_repo_root) ==
          search_roots.end()) {
    search_roots.push_back(source_repo_root);
  }

  for (const std::string& root : search_roots) {
    if (has_path_component(path)) {
      const std::string root_candidate = join_path(root, path);
      if (file_exists(root_candidate)) {
        return root_candidate;
      }
      continue;
    }

    const std::string test_vector_candidate =
        join_path(join_path(root, "tb/test_vectors"), path);
    if (file_exists(test_vector_candidate)) {
      return test_vector_candidate;
    }

    const std::string root_candidate = join_path(root, path);
    if (file_exists(root_candidate)) {
      return root_candidate;
    }
  }

  return path;
}

std::string read_text_file(const std::string& path) {
  std::ifstream stream(path);
  if (!stream) {
    throw std::runtime_error("Could not open file '" + path + "'");
  }
  std::ostringstream contents;
  contents << stream.rdbuf();
  return contents.str();
}

std::string trim(std::string value) {
  value.erase(
      value.begin(),
      std::find_if(value.begin(), value.end(), [](unsigned char ch) {
        return !std::isspace(ch);
      }));
  value.erase(
      std::find_if(value.rbegin(), value.rend(), [](unsigned char ch) {
        return !std::isspace(ch);
      }).base(),
      value.end());
  return value;
}

std::uint32_t parse_u32(const std::string& token) {
  return static_cast<std::uint32_t>(std::stoul(token, nullptr, 0));
}

std::string strip_0x_prefix(std::string value) {
  if (value.rfind("0x", 0) == 0 || value.rfind("0X", 0) == 0) {
    return value.substr(2);
  }
  return value;
}

std::uint32_t extract_hex_word_lsb_first(
    const std::string& raw_hex,
    std::size_t word_idx,
    std::size_t hex_chars_per_word) {
  std::string hex = strip_0x_prefix(trim(raw_hex));
  if (hex.empty()) {
    return 0;
  }

  const std::size_t total_chars = hex.size();
  const std::size_t word_start_from_end = word_idx * hex_chars_per_word;

  // Word begins entirely beyond the string (all zero-extended bits)
  if (word_start_from_end >= total_chars) {
    return 0;
  }

  const std::size_t end = total_chars - word_start_from_end;
  // Partial MSB word: begin clamps to 0 rather than underflowing
  const std::size_t begin = (end >= hex_chars_per_word) ? (end - hex_chars_per_word) : 0;
  return parse_u32("0x" + hex.substr(begin, end - begin));
}

void load_memfile_map(
    const std::string& path,
    std::unordered_map<std::uint32_t, std::string>* out_map) {
  out_map->clear();

  const std::string resolved_path = resolve_input_path(path);
  std::ifstream stream(resolved_path);
  if (!stream) {
    throw std::runtime_error("Could not open mem file '" + path + "'");
  }

  std::string line;
  while (std::getline(stream, line)) {
    line = trim(line);
    if (line.empty() || line[0] == '/') {
      continue;
    }
    if (line[0] != '@') {
      continue;
    }

    const std::size_t space_pos = line.find_first_of(" \t");
    if (space_pos == std::string::npos) {
      continue;
    }

    const std::string addr_str = line.substr(1, space_pos - 1);
    const std::string data_str = trim(line.substr(space_pos + 1));
    (*out_map)[parse_u32("0x" + addr_str)] = data_str;
  }
}

void load_cta_desc_hex(const std::string& path) {
  const std::string resolved_path = resolve_input_path(path);
  std::ifstream stream(resolved_path);
  if (!stream) {
    throw std::runtime_error("Could not open CTA descriptor mem '" + path + "'");
  }

  g_cta_hex.clear();
  std::string line;
  while (std::getline(stream, line)) {
    line = trim(line);
    if (line.empty() || line[0] == '/') {
      continue;
    }
    if (line[0] != '@') {
      continue;
    }
    const std::size_t space_pos = line.find_first_of(" \t");
    if (space_pos == std::string::npos) {
      continue;
    }
    g_cta_hex = trim(line.substr(space_pos + 1));
    break;
  }

  if (g_cta_hex.empty()) {
    throw std::runtime_error("CTA descriptor mem '" + path + "' had no data line");
  }
}

void load_runtime_json(const std::string& path) {
  const std::string text = read_text_file(resolve_input_path(path));

  for (std::uint32_t idx = 0; idx < 8; ++idx) {
    const std::regex csr_re(
        "\"csrX" + std::to_string(idx) + "\"\\s*:\\s*([0-9]+)");
    std::smatch match;
    if (!std::regex_search(text, match, csr_re)) {
      throw std::runtime_error(
          "runtime JSON missing required csrX" + std::to_string(idx));
    }
    g_csr_values[idx] = parse_u32(match[1].str());
  }

  g_expected_writes.clear();
  g_observed_write_idx = 0;
  g_error_count = 0;

  const std::regex write_re(
      "\\{[^\\{\\}]*\"addr\"\\s*:\\s*([0-9]+)[^\\{\\}]*\"data\"\\s*:\\s*([0-9]+)"
      "(?:[^\\{\\}]*\"strb\"\\s*:\\s*([0-9]+))?[^\\{\\}]*\\}");
  auto begin = std::sregex_iterator(text.begin(), text.end(), write_re);
  auto end = std::sregex_iterator();
  for (auto it = begin; it != end; ++it) {
    const std::smatch& match = *it;
    ExpectedWrite expected{};
    expected.addr = parse_u32(match[1].str());
    expected.data = parse_u32(match[2].str());
    expected.strb = match[3].matched ? parse_u32(match[3].str()) : 0x3;
    g_expected_writes.push_back(expected);
  }
}

std::uint32_t meta_read16(std::uint32_t byte_addr) {
  const std::uint32_t line_addr = byte_addr / kMetaWordBytes;
  const std::uint32_t beat_idx = (byte_addr % kMetaWordBytes) / kFetchBeatBytes;
  const auto it = g_meta_words.find(line_addr);
  if (it == g_meta_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, beat_idx, 4);
}

std::uint32_t bitstream_read16(std::uint32_t byte_addr) {
  const std::uint32_t word_addr = byte_addr / kFetchBeatBytes;
  const auto it = g_bitstream_words.find(word_addr);
  if (it == g_bitstream_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, 0, 4);
}

std::uint32_t meta_read32(std::uint32_t byte_addr) {
  const std::uint32_t line_addr = byte_addr / kMetaWordBytes;
  const std::uint32_t beat_idx = (byte_addr % kMetaWordBytes) / 4u;
  const auto it = g_meta_words.find(line_addr);
  if (it == g_meta_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, beat_idx, 8);
}

std::uint32_t bitstream_read32(std::uint32_t byte_addr) {
  const std::uint32_t word_addr = byte_addr / 4u;
  const auto it = g_bitstream_words.find(word_addr);
  if (it == g_bitstream_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, 0, 8);
}

}  // namespace

extern "C" {

void dice_core_tb_init(
    const char* cta_desc_mem_file,
    const char* meta_mem_file,
    const char* bitstream_mem_file,
    const char* runtime_json_file) {
  g_init_error.clear();
  g_cta_hex.clear();
  g_meta_words.clear();
  g_bitstream_words.clear();
  std::fill(std::begin(g_csr_values), std::end(g_csr_values), 0u);
  g_expected_writes.clear();
  g_observed_write_idx = 0;
  g_error_count = 0;

  try {
    if (!cta_desc_mem_file || !meta_mem_file || !bitstream_mem_file ||
        !runtime_json_file) {
      throw std::runtime_error("dice_core_tb_init: null input path");
    }

    load_cta_desc_hex(cta_desc_mem_file);
    load_memfile_map(meta_mem_file, &g_meta_words);
    load_memfile_map(bitstream_mem_file, &g_bitstream_words);
    load_runtime_json(runtime_json_file);
  } catch (const std::exception& e) {
    g_init_error = e.what();
  } catch (...) {
    g_init_error = "Unknown exception in dice_core_tb_init";
  }
}

unsigned int dice_core_tb_has_init_error() {
  return g_init_error.empty() ? 0u : 1u;
}

const char* dice_core_tb_get_init_error() {
  return g_init_error.c_str();
}

unsigned int dice_core_tb_get_cta_desc_word(unsigned int word_idx) {
  return extract_hex_word_lsb_first(g_cta_hex, word_idx, 8);
}

unsigned int dice_core_tb_get_csr(unsigned int csr_idx) {
  if (csr_idx >= 8) {
    throw std::runtime_error("dice_core_tb_get_csr: csr_idx out of range");
  }
  return g_csr_values[csr_idx];
}

unsigned int dice_core_tb_meta_read16(unsigned int byte_addr) {
  return meta_read16(byte_addr);
}

unsigned int dice_core_tb_bitstream_read16(unsigned int byte_addr) {
  return bitstream_read16(byte_addr);
}

unsigned int dice_core_tb_meta_read32(unsigned int byte_addr) {
  return meta_read32(byte_addr);
}

unsigned int dice_core_tb_bitstream_read32(unsigned int byte_addr) {
  return bitstream_read32(byte_addr);
}

unsigned int dice_core_tb_axi_read16(unsigned int addr) {
  return addr & 0xFFFFu;
}

void dice_core_tb_record_axi_write(
    unsigned int addr,
    unsigned int data,
    unsigned int strb) {
  if (g_expected_writes.empty()) {
    return;
  }

  if (g_observed_write_idx >= g_expected_writes.size()) {
    ++g_error_count;
    return;
  }

  const ExpectedWrite& expected = g_expected_writes[g_observed_write_idx];
  if (expected.addr != addr || expected.data != (data & 0xFFFFu) ||
      expected.strb != (strb & 0x3u)) {
    ++g_error_count;
  }
  ++g_observed_write_idx;
}

unsigned int dice_core_tb_check_done() {
  if (!g_expected_writes.empty() &&
      g_observed_write_idx != g_expected_writes.size()) {
    ++g_error_count;
  }
  return g_error_count == 0 ? 1u : 0u;
}

}  // extern "C"
