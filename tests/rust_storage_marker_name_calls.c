void vf__rust_storage_dead(int x);
    //@ requires true;
    //@ ensures true;

void vf__rust_storage_live(int x);
    //@ requires true;
    //@ ensures false;

void test_storage_names(int x)
    //@ requires true;
    //@ ensures true;
{
    vf__rust_storage_dead(x);
    vf__rust_storage_live(x);
    //@ assert false; // The preceding ordinary call has no continuation.
}
