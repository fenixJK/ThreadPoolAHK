#Requires AutoHotkey v2.0
class ThreadPool {
    __New(threads := 4) {
        this.stop := false
        this.tasks := []
        this.workers := []
        this.queueMutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr")
        this.Semaphore := {
            Ptr: DllCall(
                "kernel32.dll\CreateSemaphore",
                "Ptr", 0,
                "Int", 0,
                "Int", threads,
                "Str", "Semaphore",
                "Ptr"
            ),
            amount: threads
        }
        while (!this.queueMutex) {
            this.queueMutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Ptr", 0, "Ptr")
        }
        while (!this.Semaphore.Ptr) {
            this.Semaphore.Ptr := DllCall("kernel32.dll\CreateSemaphore", "Ptr", 0, "Int", 0, "Int", threads, "Str", "Semaphore", "Ptr")
        }
        createWorker(*) {
            WorkerThread(tp, Semaphore, mutex, *) {
                while true {
                    if DllCall("WaitForSingleObject", "Ptr", Semaphore, "UInt", 0xFFFFFFFF) != 0
                        continue
                    if DllCall("WaitForSingleObject", "Ptr", mutex, "UInt", 0xFFFFFFFF) != 0
                        continue
                    if (tp.stop)
                        break
                    if tp.tasks.Length > 0 {
                        task := this.tasks.RemoveAt(1)
                        DllCall("ReleaseMutex", "Ptr", mutex)
                        if IsSet(task) && Type(task) = "Func" {
                            task()
                        }
                    } else DllCall("ReleaseMutex", "Ptr", mutex)
                }
            }
            worker := {}
            worker.state := "Waiting"
            func := CallbackCreate(WorkerThread.Bind(this, this.Semaphore.Ptr, this.queueMutex))
            worker.threadHandle := DllCall(
                "CreateThread",
                "Ptr", 0,
                "UInt", 0,
                "Ptr", func,
                "Ptr", 0,
                "UInt", 0,
                "UInt*", 0,
                "Ptr")
            this.workers.Push(worker)
        }
        this.newWorker := createWorker
        Loop threads {
            this.newWorker
            ThreadPool.HyperSleep(50, "us", 300)
        }
    }
    ; In Progress
    /*addThreads(threads) {
        if !(IsNumber(threads) && threads > 0)
            return 0
        this.Semaphore.amount := threads + this.Semaphore.amount
        DllCall("ReleaseSemaphore", "Ptr", this.Semaphore.Ptr, "Int", this.Semaphore.amount, "Ptr", 0)
        DllCall("CloseHandle", "Ptr", this.Semaphore.Ptr)
        this.Semaphore.Ptr := DllCall(
            "kernel32.dll\CreateSemaphore",
            "Ptr", 0,
            "Int", 0,
            "Int", this.Semaphore.amount,
            "Str", "Semaphore",
            "Ptr")
        Loop threads {
            this.newWorker()
            ThreadPool.HyperSleep(50, "us", 300)
        }
    }*/

    enqueue(task) {
        if !Type(task) = "Func" { 
            throw "Invalid task"
        }
        DllCall("WaitForSingleObject", "Ptr", this.queueMutex, "UInt", 0xFFFFFFFF)
        this.tasks.Push(task)
        DllCall("ReleaseMutex", "Ptr", this.queueMutex)
        DllCall("ReleaseSemaphore", "Ptr", this.Semaphore.Ptr, "Int", 1, "Ptr", 0)
        ThreadPool.HyperSleep(50, "us")
    }

    stopThreads() {
        this.stop := true
        DllCall("ReleaseSemaphore", "Ptr", this.Semaphore.Ptr, "Int", this.Semaphore.amount, "Ptr", 0)
        for worker in this.workers {
            DllCall("WaitForSingleObject", "Ptr", worker.threadHandle, "UInt", 0xFFFFFFFF)
            DllCall("CloseHandle", "Ptr", worker.threadHandle)
        }
    }

    __Delete() {
        this.stopThreads()
        DllCall("CloseHandle", "Ptr", this.queueMutex)
        DllCall("CloseHandle", "Ptr", this.Semaphore.Ptr)
    }

    static HyperSleep(time, unit := "ns", threshold := 30000) {
        static freq := (DllCall("QueryPerformanceFrequency", "Int64*", &f := 0), f)
        static freqNs := freq / 1000000000
        static freqUs := freq / 1000000
        static freqMs := freq / 1000
        DllCall("QueryPerformanceCounter", "Int64*", &begin := 0)
        if (unit = "ms") {
            finish := begin + time * freqMs
        } else if (unit = "us") {
            finish := begin + time * freqUs
        } else {
            finish := begin + time * freqNs
        }
        current := 0  
        while (current < finish) {
            DllCall("QueryPerformanceCounter", "Int64*", &current := 0)
            if ((finish - current) > threshold) {
                DllCall("Winmm.dll\timeBeginPeriod", "UInt", 1)
                DllCall("Sleep", "UInt", 1)
                DllCall("Winmm.dll\timeEndPeriod", "UInt", 1)
            }
        }
    }
}