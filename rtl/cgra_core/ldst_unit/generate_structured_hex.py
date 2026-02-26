def generate_universal_pattern_hex():
    with open("test_cases.hex", 'w') as f:
        for i in range(4096):
            # Word 3 | Word 2 | Word 1 | Word 0
            # Each word is exactly 16 hex characters (64 bits)
            w3 = "3333333333333333"
            w2 = "2222222222222222"
            w1 = "1111111111111111"
            w0 = "00000000deadbeef" # Clean 64-bit word with deadbeef
            
            # Combine into a single 256-bit line (64 hex characters)
            line = w3 + w2 + w1 + w0
            f.write(line + "\n")

generate_universal_pattern_hex()