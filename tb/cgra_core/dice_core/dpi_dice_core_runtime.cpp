#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr std::uint32_t kMetaWordBytes = 256;
constexpr std::uint32_t kFetchBeatBytes16 = 2;
constexpr std::uint32_t kFetchBeatBytes32 = 4;

// Hard cap on the per-CTA override table (avoids an unbounded runtime.json
// blowing memory). Plenty for any planned 1D grid.
constexpr std::size_t kMaxCTAs = 4096;

struct ExpectedWrite {
  std::uint32_t addr;
  std::uint32_t data;
  std::uint32_t strb;
};

std::string g_cta_hex;
std::unordered_map<std::uint32_t, std::string> g_meta_words;
std::unordered_map<std::uint32_t, std::string> g_bitstream_words;
std::uint32_t g_csr_values[8] = {};

// Per-CTA CSR override table parsed from runtime.per_cta_csr_overrides.
// Multi-CTA kernels list which CSRs change per dispatch (typically array
// bases that shift by +stride per CTA); strides/scalars are absent from
// each entry and fall back to the launch g_csr_values[].
//
//   g_per_cta_csr[c][i]     = override value for csrX{i} on CTA c
//   g_per_cta_present[c][i] = true if that entry was explicitly given
//                             (false = caller should fall back to launch CSR)
//
// Empty when the runtime.json has no per_cta_csr_overrides key; single-CTA
// kernels see size()==0 and the TB's grid loop collapses to one iteration.
std::vector<std::array<std::uint32_t, 8>> g_per_cta_csr;
std::vector<std::array<bool, 8>>          g_per_cta_present;

std::vector<ExpectedWrite> g_expected_writes;
std::vector<bool> g_expected_matched;
std::vector<ExpectedWrite> g_actual_writes;  // all observed AXI writes
std::uint32_t g_observed_write_count = 0;
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
  if (word_idx * hex_chars_per_word >= total_chars) {
    return 0;
  }

  const std::size_t end = total_chars - word_idx * hex_chars_per_word;
  const std::size_t begin = (end > hex_chars_per_word) ? (end - hex_chars_per_word) : 0;
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

// Parse runtime.per_cta_csr_overrides[] into g_per_cta_csr / g_per_cta_present.
// Each entry has the shape:
//   { "cta_id": {"x": N, "y": 0, "z": 0},
//     "csr_values": { "csrXk": V, ... }  (any subset of csrX0..7) }
// CTAs not listed get no entry; CSRs missing from a listed CTA stay 'absent'.
// The runtime.axi.expected_writes regex above also matches the inner csr
// digits, but we restrict here by first slicing the substring between the
// outer "per_cta_csr_overrides" "[" and its matching "]".
void parse_per_cta_overrides(const std::string& text) {
  g_per_cta_csr.clear();
  g_per_cta_present.clear();

  const std::regex header_re("\"per_cta_csr_overrides\"\\s*:\\s*\\[");
  std::smatch hm;
  if (!std::regex_search(text, hm, header_re)) {
    return;  // single-CTA kernels: no override table, leave vectors empty
  }
  std::size_t cursor = static_cast<std::size_t>(hm.position()) + hm.length();

  // Walk balanced brackets to find the array's matching ']'.
  std::size_t depth = 1;
  std::size_t array_end = cursor;
  while (array_end < text.size() && depth > 0) {
    const char c = text[array_end];
    if      (c == '[') ++depth;
    else if (c == ']') --depth;
    if (depth > 0) ++array_end;
  }
  if (depth != 0) return;
  const std::string array_text = text.substr(cursor, array_end - cursor);

  // Iterate per-CTA objects { ... } at top level of the array.
  std::size_t i = 0;
  while (i < array_text.size()) {
    while (i < array_text.size() && array_text[i] != '{') ++i;
    if (i >= array_text.size()) break;
    const std::size_t obj_start = i;
    std::size_t obj_depth = 1;
    ++i;
    while (i < array_text.size() && obj_depth > 0) {
      const char c = array_text[i];
      if      (c == '{') ++obj_depth;
      else if (c == '}') --obj_depth;
      if (obj_depth > 0) ++i;
    }
    if (obj_depth != 0) break;
    const std::size_t obj_end = i;
    ++i;
    const std::string entry = array_text.substr(obj_start, obj_end - obj_start + 1);

    // cta_id.x — match within a "cta_id" : { ... } subobject.
    std::uint32_t cta_x = 0;
    {
      const std::regex cta_re(
          "\"cta_id\"\\s*:\\s*\\{[^\\}]*\"x\"\\s*:\\s*([0-9]+)");
      std::smatch m;
      if (!std::regex_search(entry, m, cta_re)) continue;
      cta_x = parse_u32(m[1].str());
    }
    if (cta_x >= kMaxCTAs) continue;

    // Grow tables sparsely (intermediate CTAs may have no overrides at all).
    while (g_per_cta_csr.size() <= cta_x) {
      g_per_cta_csr.push_back({0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u});
      g_per_cta_present.push_back({false, false, false, false,
                                   false, false, false, false});
    }

    for (std::uint32_t k = 0; k < 8; ++k) {
      const std::regex csr_re(
          "\"csrX" + std::to_string(k) + "\"\\s*:\\s*([0-9]+)");
      std::smatch m;
      if (std::regex_search(entry, m, csr_re)) {
        g_per_cta_csr[cta_x][k]     = parse_u32(m[1].str());
        g_per_cta_present[cta_x][k] = true;
      }
    }
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
  g_expected_matched.clear();
  g_actual_writes.clear();
  g_observed_write_count = 0;
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
  g_expected_matched.assign(g_expected_writes.size(), false);

  parse_per_cta_overrides(text);
}

std::uint32_t meta_read16(std::uint32_t byte_addr) {
  const std::uint32_t line_addr = byte_addr / kMetaWordBytes;
  const std::uint32_t beat_idx = (byte_addr % kMetaWordBytes) / kFetchBeatBytes16;
  const auto it = g_meta_words.find(line_addr);
  if (it == g_meta_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, beat_idx, 4);
}

std::uint32_t meta_read32(std::uint32_t byte_addr) {
  const std::uint32_t line_addr = byte_addr / kMetaWordBytes;
  const std::uint32_t beat_idx = (byte_addr % kMetaWordBytes) / kFetchBeatBytes32;
  const auto it = g_meta_words.find(line_addr);
  if (it == g_meta_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, beat_idx, 8);
}

std::uint32_t bitstream_read16(std::uint32_t byte_addr) {
  const std::uint32_t word_addr = byte_addr / kFetchBeatBytes32;
  const std::uint32_t halfword_idx = (byte_addr % kFetchBeatBytes32) / kFetchBeatBytes16;
  const auto it = g_bitstream_words.find(word_addr);
  if (it == g_bitstream_words.end()) {
    return 0;
  }
  return extract_hex_word_lsb_first(it->second, halfword_idx, 4);
}

std::uint32_t bitstream_read32(std::uint32_t byte_addr) {
  const std::uint32_t word_addr = byte_addr / kFetchBeatBytes32;
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
  g_per_cta_csr.clear();
  g_per_cta_present.clear();
  g_expected_writes.clear();
  g_expected_matched.clear();
  g_actual_writes.clear();
  g_observed_write_count = 0;
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

// Number of CTAs in the per-CTA CSR override table (0 if the runtime.json
// has no per_cta_csr_overrides key, i.e. single-CTA kernels).
unsigned int dice_core_tb_num_ctas() {
  return static_cast<unsigned int>(g_per_cta_csr.size());
}

// Effective csrX{csr_idx} for CTA cta_idx. Falls back to the launch-time
// g_csr_values[csr_idx] whenever the override is absent (override table
// missing, cta_idx out of range, or this specific CSR not listed in the
// entry). This is what makes the loop transparent for single-CTA kernels:
// dice_core_tb_get_per_cta_csr(0, i) == dice_core_tb_get_csr(i) when no
// overrides were parsed.
unsigned int dice_core_tb_get_per_cta_csr(unsigned int cta_idx,
                                          unsigned int csr_idx) {
  if (csr_idx >= 8) {
    throw std::runtime_error(
        "dice_core_tb_get_per_cta_csr: csr_idx out of range");
  }
  if (cta_idx < g_per_cta_csr.size() && g_per_cta_present[cta_idx][csr_idx]) {
    return g_per_cta_csr[cta_idx][csr_idx];
  }
  return g_csr_values[csr_idx];
}

unsigned int dice_core_tb_meta_read16(unsigned int byte_addr) {
  return meta_read16(byte_addr);
}

unsigned int dice_core_tb_meta_read32(unsigned int byte_addr) {
  return meta_read32(byte_addr);
}

unsigned int dice_core_tb_bitstream_read16(unsigned int byte_addr) {
  return bitstream_read16(byte_addr);
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
  const std::uint32_t d = data & 0xFFFFu;
  const std::uint32_t s = strb & 0x3u;

  g_actual_writes.push_back({addr, d, s});

  if (g_expected_writes.empty()) {
    return;
  }

  ++g_observed_write_count;

  for (std::size_t i = 0; i < g_expected_writes.size(); ++i) {
    if (g_expected_matched[i]) {
      continue;
    }
    const ExpectedWrite& exp = g_expected_writes[i];
    if (exp.addr == addr && exp.data == d && exp.strb == s) {
      g_expected_matched[i] = true;
      return;
    }
  }

  ++g_error_count;
  fprintf(stderr, "[AXI-CHK] UNEXPECTED write: addr=0x%04x data=0x%04x strb=0x%x\n",
          addr, d, s);
}

unsigned int dice_core_tb_check_done() {
  std::size_t missing_count = 0;
  if (!g_expected_writes.empty()) {
    for (std::size_t i = 0; i < g_expected_writes.size(); ++i) {
      if (!g_expected_matched[i]) {
        ++g_error_count;
        ++missing_count;
      }
    }
  }

  if (g_error_count != 0) {
    fprintf(stderr, "\n========== AXI WRITE VERIFICATION DIFF ==========\n");
    fprintf(stderr, "Expected %zu writes, observed %zu writes, %u errors\n",
            g_expected_writes.size(), g_actual_writes.size(), g_error_count);

    // Print expected writes with match status
    fprintf(stderr, "\n--- Expected writes ---\n");
    fprintf(stderr, "%4s  %6s  %6s  %4s  %s\n",
            "idx", "addr", "data", "strb", "status");
    for (std::size_t i = 0; i < g_expected_writes.size(); ++i) {
      const auto& e = g_expected_writes[i];
      fprintf(stderr, "[%3zu] 0x%04x  0x%04x  0x%x   %s\n",
              i, e.addr, e.data, e.strb,
              g_expected_matched[i] ? "OK" : "MISSING");
    }

    // Print actual writes, flagging unexpected ones
    fprintf(stderr, "\n--- Actual writes (in order) ---\n");
    fprintf(stderr, "%4s  %6s  %6s  %4s  %s\n",
            "idx", "addr", "data", "strb", "status");
    for (std::size_t i = 0; i < g_actual_writes.size(); ++i) {
      const auto& a = g_actual_writes[i];
      // Check if this write matches any expected entry
      bool matched = false;
      for (std::size_t j = 0; j < g_expected_writes.size(); ++j) {
        const auto& e = g_expected_writes[j];
        if (e.addr == a.addr && e.data == a.data && e.strb == a.strb) {
          matched = true;
          break;
        }
      }
      fprintf(stderr, "[%3zu] 0x%04x  0x%04x  0x%x   %s\n",
              i, a.addr, a.data, a.strb,
              matched ? "OK" : "UNEXPECTED");
    }

    // Side-by-side diff sorted by address for easy comparison
    fprintf(stderr, "\n--- Per-address diff (sorted by addr) ---\n");
    fprintf(stderr, "%6s | %12s | %12s | %s\n",
            "addr", "expected", "actual", "status");
    fprintf(stderr, "-------+--------------+--------------+--------\n");

    // Build address->data maps
    std::map<std::uint32_t, std::uint32_t> exp_by_addr;
    std::map<std::uint32_t, std::uint32_t> act_by_addr;
    for (const auto& e : g_expected_writes) exp_by_addr[e.addr] = e.data;
    for (const auto& a : g_actual_writes) act_by_addr[a.addr] = a.data;

    // Collect all addresses
    std::set<std::uint32_t> all_addrs;
    for (const auto& kv : exp_by_addr) all_addrs.insert(kv.first);
    for (const auto& kv : act_by_addr) all_addrs.insert(kv.first);

    for (std::uint32_t addr : all_addrs) {
      auto eit = exp_by_addr.find(addr);
      auto ait = act_by_addr.find(addr);
      char exp_str[16] = "---";
      char act_str[16] = "---";
      const char* status = "OK";

      if (eit != exp_by_addr.end()) snprintf(exp_str, sizeof(exp_str), "0x%04x", eit->second);
      if (ait != act_by_addr.end()) snprintf(act_str, sizeof(act_str), "0x%04x", ait->second);

      if (eit == exp_by_addr.end()) {
        status = "EXTRA";
      } else if (ait == act_by_addr.end()) {
        status = "MISSING";
      } else if (eit->second != ait->second) {
        status = "MISMATCH";
      }

      // Only print mismatches and problems to reduce noise
      if (eit == exp_by_addr.end() || ait == act_by_addr.end() ||
          eit->second != ait->second) {
        fprintf(stderr, "0x%04x | %12s | %12s | %s\n",
                addr, exp_str, act_str, status);
      }
    }

    // Print summary of matching entries
    std::size_t match_count = 0;
    for (std::uint32_t addr : all_addrs) {
      auto eit = exp_by_addr.find(addr);
      auto ait = act_by_addr.find(addr);
      if (eit != exp_by_addr.end() && ait != act_by_addr.end() &&
          eit->second == ait->second) {
        ++match_count;
      }
    }
    fprintf(stderr, "\n%zu/%zu addresses match, %zu mismatches/missing/extra\n",
            match_count, all_addrs.size(), all_addrs.size() - match_count);
    fprintf(stderr, "===================================================\n\n");
  }

  return g_error_count == 0 ? 1u : 0u;
}

}  // extern "C"
