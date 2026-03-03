# Data word size
word_size = 32
# Number of words in the memory
num_words = 512

# Technology to use in $OPENRAM_TECH
tech_name = "freepdk45"
# Process corners to characterize
process_corners = ["TT", "FF", "SS"]
# Voltage corners to characterize
supply_voltages = [1.1]
# Temperature corners to characterize
temperatures = [25, 125, 0]

# Output directory for the results
output_path = "temp"
# Output file base name
output_name = "sram_512x32"

# Disable analytical models for full characterization (WARNING: slow!)
# analytical_delay = False

# To force this to use magic and netgen for DRC/LVS/PEX
# Could be calibre for FreePDK45
drc_name = "magic"
lvs_name = "netgen"
pex_name = "magic"
