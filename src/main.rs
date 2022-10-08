use std::env;
use wasmtime::*;

// Small program to test and interact with the WebAssembly allocators.
fn main() -> Result<(), Box<dyn std::error::Error>> {

    // Get command line arguments
    let args: Vec<String> = env::args().collect();

    // If no arguments ask for .wat path
    if args.len() < 2 {
        println!("Please specify the allocator you want to use e.g. 'cargo run -- src/1_minimal.wat'");
        return Ok(())
    }

    // Instantiate WebAssembly module from .wat file
    let mut wasm_store: Store<()> = Store::default();
    let module = Module::from_file(wasm_store.engine(), &args[1])?;
    let instance = Instance::new(&mut wasm_store, &module, &[])?;

    // Get callable references to the functions
    let alloc = instance.get_typed_func::<(i32), i32, _>(&mut wasm_store, "alloc")?;
    let dealloc = instance.get_typed_func::<(i32), (), _>(&mut wasm_store, "dealloc")?;
    let realloc = instance.get_typed_func::<(i32, i32), i32, _>(&mut wasm_store, "realloc")?;
    let store = instance.get_typed_func::<(i32, i32), (), _>(&mut wasm_store, "store")?;
    let load = instance.get_typed_func::<(i32), i32, _>(&mut wasm_store, "load")?;
    let size = instance.get_typed_func::<(), i32, _>(&mut wasm_store, "size")?;
    let grow = instance.get_typed_func::<(i32), i32, _>(&mut wasm_store, "grow")?;

    // Test memory growing
    // println!("size(): {:?}", size.call(&mut wasm_store, ())?);
    // println!("grow(1): {:?}", grow.call(&mut wasm_store, 1)?);
    // println!("size(): {:?}", size.call(&mut wasm_store, ())?);

    // // Test loading and storing
    // println!("load(0): {:?}", load.call(&mut wasm_store, 0)?);
    // println!("store(0, 1): {:?}", store.call(&mut wasm_store, (0, 1))?);
    // println!("load(0): {:?}", load.call(&mut wasm_store, 0)?);

    // Test a load beyond the first memory page
    // println!("load(x): {:?}", load.call(&mut wasm_store, 65532)?); // Works with 65532 but not 65533 because there are only 65536 bytes in a page

    Ok(())
}
