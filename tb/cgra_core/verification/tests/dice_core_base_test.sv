// dice_core_base_test
// -------------------
// Builds the env and wraps run_body() in objection raise/drop.
// All other tests in this directory inherit from this class. Not runnable
// on its own — subclasses override run_body() to load data and dispatch a CTA.
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
