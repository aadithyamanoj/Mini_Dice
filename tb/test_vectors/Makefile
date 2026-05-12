PYTHON ?= python3

TESTS := full_mul_array simple_branching

FULL_MUL_ARRAY_FDR_JSONS := \
	fdr_meta_load_mul_array_a.json \
	fdr_meta_load_mul_array_b.json \
	fdr_meta_mul_array.json \
	fdr_meta_compute_store_addrs.json \
	fdr_meta_store_mul_array.json

SIMPLE_BRANCHING_FDR_JSONS := \
	fdr_meta_simple_branching_load_mul_array_a.json \
	fdr_meta_simple_branching_load_mul_array_b.json \
	fdr_meta_simple_branching_gen_tid_nonzero_pred.json \
	fdr_meta_simple_branching_mul_array.json \
	fdr_meta_simple_branching_add_array.json \
	fdr_meta_simple_branching_compute_store_addrs.json \
	fdr_meta_simple_branching_store_mul_array.json

TEST_VECTOR_JSONS := $(addsuffix _test_vector.json,$(TESTS))
TEST_DATA := $(foreach test,$(TESTS), \
	$(test)_test_vector_meta.mem \
	$(test)_test_vector_cta_desc.mem \
	$(test)_test_vector_bitstream.mem \
	$(test)_test_vector_runtime.json)
GENERATED_JSONS := \
	$(FULL_MUL_ARRAY_FDR_JSONS) \
	$(SIMPLE_BRANCHING_FDR_JSONS) \
	$(TEST_VECTOR_JSONS)

.PHONY: all clean full_mul_array simple_branching

all: $(TEST_DATA)

full_mul_array: full_mul_array_test_vector_meta.mem \
	full_mul_array_test_vector_cta_desc.mem \
	full_mul_array_test_vector_bitstream.mem \
	full_mul_array_test_vector_runtime.json

simple_branching: simple_branching_test_vector_meta.mem \
	simple_branching_test_vector_cta_desc.mem \
	simple_branching_test_vector_bitstream.mem \
	simple_branching_test_vector_runtime.json

full_mul_array_test_vector.json $(FULL_MUL_ARRAY_FDR_JSONS): gen_fdr_metadata.py
	$(PYTHON) $< --kernel full_mul_array --output-dir .

simple_branching_test_vector.json $(SIMPLE_BRANCHING_FDR_JSONS): gen_fdr_metadata.py
	$(PYTHON) $< --kernel simple-branching --output-dir .

%_test_vector_meta.mem %_test_vector_cta_desc.mem %_test_vector_bitstream.mem %_test_vector_runtime.json: %_test_vector.json gen_memfile.py
	$(PYTHON) gen_memfile.py $< --output-dir .

clean:
	rm -f $(TEST_DATA) $(GENERATED_JSONS)
