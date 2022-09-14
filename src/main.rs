use std::{env, fs};
use wasmer::{Store, Module, Instance, Value as WasmerValue, imports, wat2wasm};

// Small program to test and interact with the WebAssembly allocators.
fn main() -> Result<(), Box<dyn std::error::Error>> {

    // Get command line arguments
    let args: Vec<String> = env::args().collect();

    // If no arguments ask for .wat path
    if args.len() < 2 {
        println!("Please specify the allocator you want to use e.g. 'cargo run -- src/1_minimal.wat'");
        return Ok(())
    }

    // Read .wat file and convert to WebAssembly bytes
    let file_data = fs::read(&args[1])?;
    let wasm_bytes = wat2wasm(&file_data)?;

    // Compile and instantiate the WebAssembly module
    let store = Store::default();
    let module = Module::new(&store, &wasm_bytes)?;
    let instance = Instance::new(&module, &imports! {})?;

    // Get callable references to the functions
    let alloc_func = instance.exports.get_function("alloc").unwrap();
    let alloc = |s: i32| alloc_func.call(&[WasmerValue::I32(s)]);

    let dealloc_func = instance.exports.get_function("dealloc").unwrap();
    let dealloc = |a: i32| dealloc_func.call(&[WasmerValue::I32(a)]);

    let store_func = instance.exports.get_function("store").unwrap();
    let store = |a: i32, v: i32| store_func.call(&[WasmerValue::I32(a), WasmerValue::I32(v)]);
    
    let load_func = instance.exports.get_function("load").unwrap();
    let load = |a: i32| load_func.call(&[WasmerValue::I32(a)]);
    
    let size_func = instance.exports.get_function("size").unwrap();
    let size = || size_func.call(&[] as &[WasmerValue; 0]);

    let grow_func = instance.exports.get_function("grow").unwrap();
    let grow = |s: i32| grow_func.call(&[WasmerValue::I32(s)]);

    // Test memory growing
    // println!("size(): {:?}", size()?);
    // println!("grow(1): {:?}", grow(1)?);
    // println!("size(): {:?}", size()?);
    
    // Test loading and storing
    // println!("load(0): {:?}", load(0)?);
    // println!("store(0, 1): {:?}", store(0, 1)?);
    // println!("load(0): {:?}", load(0)?);

    // Test a load beyond the first memory page
    // println!("load(x): {:?}", load(65532)?); // Works with 65532 but not 65533 because there are only 65536 bytes in a page

    Ok(())
}
