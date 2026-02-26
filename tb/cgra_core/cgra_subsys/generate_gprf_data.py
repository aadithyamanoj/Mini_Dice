from prepare_rf_data import generate_rf_data

# All matrix as 1's
def my_custom_pattern(prefix, port, addr, width):
    return 1 

generate_rf_data(prefix='r', num_ports=32, depth=512, width=32,
                 outdir='rf_input', pattern_func=my_custom_pattern)