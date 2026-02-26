from prepare_rf_data import generate_rf_data

# All matrix as 1's
def my_custom_pattern(prefix, port, addr, width):
    if(port == 8 or port == 10 or port == 12 or port == 14):
        # latch C and release D, every 32 cycles.
        return (addr % 32 == 0)
    if (port == 9):
        # Switch PE internal accumulater on and off.
        return (addr % 64 < 32)
    
    if (port == 1 or port == 3 or port == 5 or port == 7):
        # enable D register writeback
        return (addr % 32 < 4)
    return 1 

generate_rf_data(prefix='p', num_ports=32, depth=512, width=1,
                 outdir='rf_input', pattern_func=my_custom_pattern)