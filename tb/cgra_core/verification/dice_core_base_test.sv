// Base test: creates the env, retrieves the vif, nothing else.
// All real tests extend this class.
class dice_core_base_test extends uvm_test;
  `uvm_component_utils(dice_core_base_test)

  dice_core_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = dice_core_env::type_id::create("env", this);
  endfunction

  // Convenience: raise/drop objection around a task
  task run_test_body(uvm_phase phase);
    phase.raise_objection(this);
    run_body(phase);
    phase.drop_objection(this);
  endtask

  virtual task run_body(uvm_phase phase);
    // Override in derived tests
  endtask

  task run_phase(uvm_phase phase);
    run_test_body(phase);
  endtask

endclass
