"""Run fresh processes under LLDB and stop on the first abnormal termination."""
import os
import lldb


def run(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    debugger.SetAsync(False)
    for attempt in range(1, 301):
        print(f"LLDB process {attempt}/300", flush=True)
        process = target.LaunchSimple(None, None, os.getcwd())
        state = process.GetState()
        output = process.GetSTDOUT(1048576)
        errors = process.GetSTDERR(1048576)
        if state != lldb.eStateExited or process.GetExitStatus() != 0:
            print(output, errors, flush=True)
            debugger.HandleCommand('process status')
            debugger.HandleCommand('thread backtrace all')
            debugger.HandleCommand('register read')
            debugger.HandleCommand('image list')
            with open(os.environ['PAYMENT_LLDB_FAILURE'], 'w') as marker:
                marker.write(f'iteration={attempt} state={state} exit={process.GetExitStatus()}\n')
            return
    os.remove(os.environ['PAYMENT_LLDB_FAILURE'])


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f payment_lldb_stress.run payment-stress')
