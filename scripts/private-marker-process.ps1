Set-StrictMode -Version Latest

# 実行系の分岐にcaller-controlledな`$env:OS`を使わず、.NETのkernel情報を正とする。
# これにより環境変数を偽装されてもcontainment方式が弱い経路へ切り替わらない。
$script:privateMarkerIsWindows =
    [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

# Windows PowerShell 5.1には子孫tree停止APIがないため、kill-on-close Jobを使う。
# direct child終了後もJob handleを保持し、pipeを握る孫processまで確実に停止する。
if ($script:privateMarkerIsWindows -and
    $null -eq ('AgenticCodingSecurityGate.PrivateMarkerJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace AgenticCodingSecurityGate
{
    public static class PrivateMarkerJob
    {
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const uint JOB_OBJECT_LIMIT_BREAKAWAY_OK = 0x00000800;
        private const uint JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK = 0x00001000;
        private const int JobObjectExtendedLimitInformation = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateJobObject(
            IntPtr jobAttributes,
            string name
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(
            IntPtr job,
            IntPtr process
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool IsProcessInJob(
            IntPtr process,
            IntPtr job,
            out bool result
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool QueryInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength,
            IntPtr returnLength
        );

        public static IntPtr CreateKillOnClose()
        {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero)
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "CreateJobObject failed."
                );
            }

            var information = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            information.BasicLimitInformation.LimitFlags =
                JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            int size = Marshal.SizeOf(
                typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)
            );
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(information, buffer, false);
                if (!SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    buffer,
                    (uint)size
                ))
                {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "SetInformationJobObject failed."
                    );
                }
                return job;
            }
            catch
            {
                CloseHandle(job);
                throw;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        public static void Assign(IntPtr job, IntPtr process)
        {
            if (!AssignProcessToJobObject(job, process))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "AssignProcessToJobObject failed."
                );
            }
        }

        public static bool Close(IntPtr job)
        {
            return job == IntPtr.Zero || CloseHandle(job);
        }

        public static bool IsCurrentProcessInOwnedJob()
        {
            bool inJob;
            if (!IsProcessInJob(GetCurrentProcess(), IntPtr.Zero, out inJob) ||
                !inJob)
            {
                return false;
            }

            int size = Marshal.SizeOf(
                typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)
            );
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                if (!QueryInformationJobObject(
                    IntPtr.Zero,
                    JobObjectExtendedLimitInformation,
                    buffer,
                    (uint)size,
                    IntPtr.Zero
                ))
                {
                    return false;
                }
                var information =
                    (JOBOBJECT_EXTENDED_LIMIT_INFORMATION)
                    Marshal.PtrToStructure(
                        buffer,
                        typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)
                    );
                uint flags =
                    information.BasicLimitInformation.LimitFlags;
                return
                    (flags & JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE) != 0 &&
                    (flags & JOB_OBJECT_LIMIT_BREAKAWAY_OK) == 0 &&
                    (flags & JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK) == 0;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }
}
'@
}

# Windows初回起動はtarget自身をsuspendedで作り、stdio以外のhandleを渡さない。
# Job割当後にだけresumeするため、native byte列とimmediate descendantを同時に守る。
if ($script:privateMarkerIsWindows -and
    $null -eq ('AgenticSecurityGateContainedProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public sealed class AgenticSecurityGateContainedProcess : IDisposable
{
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;
    private const uint CreateSuspended = 0x00000004;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint ExtendedStartupInfoPresent = 0x00080000;
    private const uint CreateNoWindow = 0x08000000;
    private const uint StartfUseStdHandles = 0x00000100;
    private const uint HandleFlagInherit = 0x00000001;
    private const uint ResumeFailed = 0xFFFFFFFF;
    private const uint WaitObject0 = 0x00000000;
    private const uint WaitTimeout = 0x00000102;
    private const uint WaitFailed = 0xFFFFFFFF;
    private static readonly IntPtr ProcThreadAttributeHandleList =
        new IntPtr(0x00020002);

    private IntPtr jobHandle;
    private IntPtr processHandle;
    private int syntheticJobCloseFailuresRemaining;
    private bool trackSyntheticJobCloseAttempts;
    private bool disposed;

    public Stream StandardInput { get; private set; }
    public Stream StandardOutput { get; private set; }
    public Stream StandardError { get; private set; }
    public static int LastSyntheticFailureProcessId { get; private set; }
    public static int LastSyntheticJobCloseAttemptCount { get; private set; }

    private AgenticSecurityGateContainedProcess(
        IntPtr childProcess,
        Stream standardInput,
        Stream standardOutput,
        Stream standardError,
        IntPtr job,
        string testFailureMode)
    {
        processHandle = childProcess;
        StandardInput = standardInput;
        StandardOutput = standardOutput;
        StandardError = standardError;
        jobHandle = job;
        trackSyntheticJobCloseAttempts =
            String.Equals(testFailureMode, "close", StringComparison.Ordinal) ||
            String.Equals(testFailureMode, "dispose", StringComparison.Ordinal);
        syntheticJobCloseFailuresRemaining =
            String.Equals(testFailureMode, "close", StringComparison.Ordinal)
                ? 2
                : (String.Equals(
                    testFailureMode,
                    "dispose",
                    StringComparison.Ordinal) ? 1 : 0);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SECURITY_ATTRIBUTES
    {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        [MarshalAs(UnmanagedType.Bool)]
        public bool bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFOEX
    {
        public STARTUPINFO StartupInfo;
        public IntPtr lpAttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreatePipe(
        out IntPtr readPipe,
        out IntPtr writePipe,
        ref SECURITY_ATTRIBUTES pipeAttributes,
        int size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetHandleInformation(
        IntPtr handle,
        uint mask,
        uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcessW(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref STARTUPINFOEX startupInfo,
        out PROCESS_INFORMATION processInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool InitializeProcThreadAttributeList(
        IntPtr attributeList,
        int attributeCount,
        int flags,
        ref IntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UpdateProcThreadAttribute(
        IntPtr attributeList,
        uint flags,
        IntPtr attribute,
        IntPtr value,
        IntPtr size,
        IntPtr previousValue,
        IntPtr returnSize);

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(
        IntPtr attributeList);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr jobAttributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        IntPtr job,
        int informationClass,
        ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetExitCodeProcess(
        IntPtr process,
        out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    private static string Quote(string value)
    {
        if (value.Length == 0)
            return "\"\"";
        if (value.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0)
            return value;

        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in value)
        {
            if (character == '\\')
            {
                slashes++;
                continue;
            }
            if (character == '"')
            {
                result.Append('\\', (slashes * 2) + 1);
                result.Append('"');
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes);
            slashes = 0;
            result.Append(character);
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }

    private static StringBuilder BuildCommandLine(
        string filePath,
        string[] arguments)
    {
        StringBuilder commandLine = new StringBuilder(Quote(filePath));
        foreach (string argument in arguments)
        {
            commandLine.Append(' ');
            commandLine.Append(Quote(argument ?? String.Empty));
        }
        return commandLine;
    }

    private static IntPtr BuildEnvironmentBlock(IDictionary environment)
    {
        List<string> entries = new List<string>();
        foreach (DictionaryEntry entry in environment)
        {
            string name = Convert.ToString(entry.Key);
            string value = Convert.ToString(entry.Value) ?? String.Empty;
            if (String.IsNullOrEmpty(name) ||
                name.IndexOf('=') >= 0 ||
                name.IndexOf('\0') >= 0 ||
                value.IndexOf('\0') >= 0)
            {
                throw new ArgumentException("Invalid child environment entry.");
            }
            entries.Add(name + "=" + value);
        }
        entries.Sort(StringComparer.OrdinalIgnoreCase);
        string block = String.Join("\0", entries.ToArray()) + "\0\0";
        return Marshal.StringToHGlobalUni(block);
    }

    private static IntPtr CreateKillOnCloseJob()
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "CreateJobObject failed.");

        JOBOBJECT_EXTENDED_LIMIT_INFORMATION information =
            new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        information.BasicLimitInformation.LimitFlags =
            JobObjectLimitKillOnJobClose;
        if (!SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformationClass,
                ref information,
                (uint)Marshal.SizeOf(
                    typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
        {
            int error = Marshal.GetLastWin32Error();
            CloseHandle(job);
            throw new Win32Exception(error, "SetInformationJobObject failed.");
        }
        return job;
    }

    private static void CloseOwnedHandle(ref IntPtr handle)
    {
        if (handle != IntPtr.Zero)
        {
            CloseHandle(handle);
            handle = IntPtr.Zero;
        }
    }

    public static AgenticSecurityGateContainedProcess StartContained(
        string filePath,
        string[] arguments,
        IDictionary environment,
        string currentDirectory,
        string testFailureMode,
        int executionDeadlineMilliseconds,
        int operationDeadlineMilliseconds)
    {
        Stopwatch operationStopwatch = Stopwatch.StartNew();

        // Self-test が直前の PID を誤認しないよう、fault injection ごとに
        // probe state を初期化する。production path では共有状態を更新しない。
        if (!String.IsNullOrEmpty(testFailureMode))
        {
            LastSyntheticFailureProcessId = 0;
            LastSyntheticJobCloseAttemptCount = 0;
        }

        IntPtr stdinRead = IntPtr.Zero;
        IntPtr stdinWrite = IntPtr.Zero;
        IntPtr stdoutRead = IntPtr.Zero;
        IntPtr stdoutWrite = IntPtr.Zero;
        IntPtr stderrRead = IntPtr.Zero;
        IntPtr stderrWrite = IntPtr.Zero;
        IntPtr environmentBlock = IntPtr.Zero;
        IntPtr attributeList = IntPtr.Zero;
        IntPtr inheritedHandleList = IntPtr.Zero;
        IntPtr job = IntPtr.Zero;
        PROCESS_INFORMATION processInformation = new PROCESS_INFORMATION();
        SafeFileHandle stdinSafeHandle = null;
        SafeFileHandle stdoutSafeHandle = null;
        SafeFileHandle stderrSafeHandle = null;
        FileStream stdout = null;
        FileStream stderr = null;
        FileStream stdin = null;
        bool processCreated = false;
        bool processAssigned = false;
        bool attributeListInitialized = false;
        try
        {
            SECURITY_ATTRIBUTES attributes = new SECURITY_ATTRIBUTES();
            attributes.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
            attributes.bInheritHandle = true;

            if (!CreatePipe(out stdinRead, out stdinWrite, ref attributes, 0) ||
                !CreatePipe(out stdoutRead, out stdoutWrite, ref attributes, 0) ||
                !CreatePipe(out stderrRead, out stderrWrite, ref attributes, 0))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "CreatePipe failed.");
            if (!SetHandleInformation(stdinWrite, HandleFlagInherit, 0) ||
                !SetHandleInformation(stdoutRead, HandleFlagInherit, 0) ||
                !SetHandleInformation(stderrRead, HandleFlagInherit, 0))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "SetHandleInformation failed.");

            // bInheritHandles=true でも child stdio 以外を渡さない。親側の
            // unrelated inheritable handle が Git やその孫へ漏れるのを防ぐ。
            IntPtr attributeListSize = IntPtr.Zero;
            InitializeProcThreadAttributeList(
                IntPtr.Zero, 1, 0, ref attributeListSize);
            if (attributeListSize == IntPtr.Zero)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "InitializeProcThreadAttributeList size query failed.");
            attributeList = Marshal.AllocHGlobal(attributeListSize);
            if (!InitializeProcThreadAttributeList(
                    attributeList, 1, 0, ref attributeListSize))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "InitializeProcThreadAttributeList failed.");
            attributeListInitialized = true;

            inheritedHandleList = Marshal.AllocHGlobal(IntPtr.Size * 3);
            Marshal.WriteIntPtr(inheritedHandleList, 0, stdinRead);
            Marshal.WriteIntPtr(inheritedHandleList, IntPtr.Size, stdoutWrite);
            Marshal.WriteIntPtr(
                inheritedHandleList, IntPtr.Size * 2, stderrWrite);
            if (!UpdateProcThreadAttribute(
                    attributeList,
                    0,
                    ProcThreadAttributeHandleList,
                    inheritedHandleList,
                    new IntPtr(IntPtr.Size * 3),
                    IntPtr.Zero,
                    IntPtr.Zero))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "UpdateProcThreadAttribute failed.");

            STARTUPINFOEX startupInfo = new STARTUPINFOEX();
            startupInfo.StartupInfo.cb =
                Marshal.SizeOf(typeof(STARTUPINFOEX));
            startupInfo.StartupInfo.dwFlags = StartfUseStdHandles;
            startupInfo.StartupInfo.hStdInput = stdinRead;
            startupInfo.StartupInfo.hStdOutput = stdoutWrite;
            startupInfo.StartupInfo.hStdError = stderrWrite;
            startupInfo.lpAttributeList = attributeList;

            job = CreateKillOnCloseJob();
            environmentBlock = BuildEnvironmentBlock(environment);
            if (operationStopwatch.ElapsedMilliseconds >=
                executionDeadlineMilliseconds)
                throw new TimeoutException(
                    "Contained child setup exceeded the execution deadline.");
            if (!CreateProcessW(
                    filePath,
                    BuildCommandLine(filePath, arguments),
                    IntPtr.Zero,
                    IntPtr.Zero,
                    true,
                    CreateSuspended |
                        CreateUnicodeEnvironment |
                        CreateNoWindow |
                        ExtendedStartupInfoPresent,
                    environmentBlock,
                    String.IsNullOrWhiteSpace(currentDirectory)
                        ? null
                        : currentDirectory,
                    ref startupInfo,
                    out processInformation))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "CreateProcessW failed.");
            }
            processCreated = true;
            if (!String.IsNullOrEmpty(testFailureMode))
                LastSyntheticFailureProcessId =
                    processInformation.dwProcessId;

            // Job 割当前の synthetic failure でも target は suspended のまま。
            // catch で terminate と wait の成否を検証してからだけ失敗を返す。
            if (String.Equals(
                    testFailureMode,
                    "assign",
                    StringComparison.Ordinal))
                throw new InvalidOperationException(
                    "Synthetic Job assignment failure.");
            if (!AssignProcessToJobObject(job, processInformation.hProcess))
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "AssignProcessToJobObject failed.");
            processAssigned = true;

            stdinSafeHandle = new SafeFileHandle(stdinWrite, true);
            stdinWrite = IntPtr.Zero;
            stdoutSafeHandle = new SafeFileHandle(stdoutRead, true);
            stdoutRead = IntPtr.Zero;
            stderrSafeHandle = new SafeFileHandle(stderrRead, true);
            stderrRead = IntPtr.Zero;
            stdin = new FileStream(
                stdinSafeHandle, FileAccess.Write, 8192, false);
            stdinSafeHandle = null;
            stdout = new FileStream(
                stdoutSafeHandle, FileAccess.Read, 8192, false);
            stdoutSafeHandle = null;
            stderr = new FileStream(
                stderrSafeHandle, FileAccess.Read, 8192, false);
            stderrSafeHandle = null;

            // Child pipe ends must be closed in the parent before resume.
            CloseOwnedHandle(ref stdinRead);
            CloseOwnedHandle(ref stdoutWrite);
            CloseOwnedHandle(ref stderrWrite);

            // Job 割当後も resume 前に失敗させ、kill-on-close と bounded wait を
            // target codeを一度も実行せず実測できるようにする。
            if (String.Equals(
                    testFailureMode,
                    "resume",
                    StringComparison.Ordinal))
                throw new InvalidOperationException(
                    "Synthetic ResumeThread failure.");
            if (operationStopwatch.ElapsedMilliseconds >=
                executionDeadlineMilliseconds)
                throw new TimeoutException(
                    "Contained child launch exceeded the execution deadline.");
            if (ResumeThread(processInformation.hThread) == ResumeFailed)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "ResumeThread failed.");
            CloseOwnedHandle(ref processInformation.hThread);

            AgenticSecurityGateContainedProcess result =
                new AgenticSecurityGateContainedProcess(
                    processInformation.hProcess,
                stdin,
                stdout,
                stderr,
                job,
                testFailureMode);
            processInformation.hProcess = IntPtr.Zero;
            stdin = null;
            stdout = null;
            stderr = null;
            job = IntPtr.Zero;
            return result;
        }
        catch (Exception launchFailure)
        {
            Exception cleanupFailure = null;
            if (processCreated)
            {
                if (processAssigned && job != IntPtr.Zero)
                {
                    // Job close failure時はhandleをfinallyの再試行用に残し、
                    // suspended processを直接terminateするfallbackも要求する。
                    IntPtr assignedJob = job;
                    if (CloseHandle(assignedJob))
                        job = IntPtr.Zero;
                    else
                    {
                        cleanupFailure = new Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "Closing the assigned Job failed.");
                        if (!TerminateProcess(
                                processInformation.hProcess,
                                1))
                        {
                            Exception terminateFailure =
                                new Win32Exception(
                                    Marshal.GetLastWin32Error(),
                                    "Fallback process termination failed.");
                            cleanupFailure = new AggregateException(
                                cleanupFailure,
                                terminateFailure);
                        }
                    }
                }
                else if (!TerminateProcess(processInformation.hProcess, 1))
                {
                    cleanupFailure = new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "Terminating the suspended process failed.");
                }

                int remainingMilliseconds = Math.Max(
                    0,
                    operationDeadlineMilliseconds -
                        (int)Math.Min(
                            Int32.MaxValue,
                            operationStopwatch.ElapsedMilliseconds));
                uint waitResult = remainingMilliseconds > 0
                    ? WaitForSingleObject(
                        processInformation.hProcess,
                        (uint)remainingMilliseconds)
                    : WaitTimeout;
                if (waitResult != WaitObject0)
                {
                    Exception waitFailure = waitResult == WaitFailed
                        ? (Exception)new Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "Waiting for launch-failure cleanup failed.")
                        : new TimeoutException(
                            "Launch-failure cleanup exceeded the operation deadline.");
                    cleanupFailure = cleanupFailure == null
                        ? waitFailure
                        : new AggregateException(cleanupFailure, waitFailure);
                }
            }
            if (cleanupFailure != null)
                throw new AggregateException(
                    "Contained child launch cleanup failed.",
                    launchFailure,
                    cleanupFailure);
            throw;
        }
        finally
        {
            if (environmentBlock != IntPtr.Zero)
                Marshal.FreeHGlobal(environmentBlock);
            if (attributeListInitialized)
                DeleteProcThreadAttributeList(attributeList);
            if (attributeList != IntPtr.Zero)
                Marshal.FreeHGlobal(attributeList);
            if (inheritedHandleList != IntPtr.Zero)
                Marshal.FreeHGlobal(inheritedHandleList);
            CloseOwnedHandle(ref stdinRead);
            CloseOwnedHandle(ref stdinWrite);
            CloseOwnedHandle(ref stdoutRead);
            CloseOwnedHandle(ref stdoutWrite);
            CloseOwnedHandle(ref stderrRead);
            CloseOwnedHandle(ref stderrWrite);
            CloseOwnedHandle(ref processInformation.hThread);
            CloseOwnedHandle(ref processInformation.hProcess);
            if (job != IntPtr.Zero)
                CloseOwnedHandle(ref job);
            if (stdout != null)
                stdout.Dispose();
            if (stderr != null)
                stderr.Dispose();
            if (stdin != null)
                stdin.Dispose();
            if (stdinSafeHandle != null)
                stdinSafeHandle.Dispose();
            if (stdoutSafeHandle != null)
                stdoutSafeHandle.Dispose();
            if (stderrSafeHandle != null)
                stderrSafeHandle.Dispose();
        }
    }

    public bool WaitForExit(int milliseconds)
    {
        return WaitForSingleObject(processHandle, (uint)milliseconds) ==
            WaitObject0;
    }

    public bool HasExited
    {
        get { return WaitForSingleObject(processHandle, 0) == WaitObject0; }
    }

    public int ExitCode
    {
        get
        {
            uint exitCode;
            if (!GetExitCodeProcess(processHandle, out exitCode))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return unchecked((int)exitCode);
        }
    }

    public void CloseJob()
    {
        if (jobHandle == IntPtr.Zero)
            return;
        if (trackSyntheticJobCloseAttempts)
            LastSyntheticJobCloseAttemptCount++;
        IntPtr handle = jobHandle;
        bool syntheticFailure = syntheticJobCloseFailuresRemaining > 0;
        if (syntheticFailure)
            syntheticJobCloseFailuresRemaining--;
        if (!syntheticFailure && CloseHandle(handle))
        {
            jobHandle = IntPtr.Zero;
            return;
        }

        int closeError = syntheticFailure
            ? 5
            : Marshal.GetLastWin32Error();
        Exception closeFailure = new Win32Exception(
            closeError,
            syntheticFailure
                ? "Synthetic Job close failure."
                : "Closing the contained Job failed.");

        // CloseHandle失敗時もJob全体へ明示terminateを試みる。handleは成功時
        // だけzero化し、callerのretry/Disposeでcloseを再試行可能に保つ。
        if (!TerminateJobObject(handle, 1))
        {
            Exception terminateFailure = new Win32Exception(
                Marshal.GetLastWin32Error(),
                "Fallback Job termination failed.");
            throw new AggregateException(closeFailure, terminateFailure);
        }
        throw closeFailure;
    }

    public void TerminateDirectProcess()
    {
        if (processHandle == IntPtr.Zero || HasExited)
            return;
        if (!TerminateProcess(processHandle, 1) && !HasExited)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "Fallback direct-process termination failed.");
    }

    public void Dispose()
    {
        if (disposed)
            return;

        List<Exception> cleanupFailures = new List<Exception>();
        bool jobClosed = false;
        try
        {
            CloseJob();
            jobClosed = true;
        }
        catch (Exception firstCloseFailure)
        {
            cleanupFailures.Add(firstCloseFailure);
            try
            {
                TerminateDirectProcess();
            }
            catch (Exception directTerminationFailure)
            {
                cleanupFailures.Add(directTerminationFailure);
            }
            try
            {
                CloseJob();
                jobClosed = true;
            }
            catch (Exception retryCloseFailure)
            {
                cleanupFailures.Add(retryCloseFailure);
            }
        }

        try
        {
            StandardInput.Dispose();
            StandardOutput.Dispose();
            StandardError.Dispose();
        }
        catch (Exception streamCleanupFailure)
        {
            cleanupFailures.Add(streamCleanupFailure);
        }
        CloseOwnedHandle(ref processHandle);

        // close成功後だけdisposedへ遷移する。retryも失敗した場合はowned Job
        // handleを保持し、callerがもう一度Disposeできる状態を残す。
        if (jobClosed && jobHandle == IntPtr.Zero)
            disposed = true;
        if (cleanupFailures.Count == 1)
            throw cleanupFailures[0];
        if (cleanupFailures.Count > 1)
            throw new AggregateException(
                "Contained process disposal failed.",
                cleanupFailures.ToArray());
    }
}
'@
}
# POSIX group signaling must distinguish ESRCH ("already gone") from EPERM
# and other failures. The kill utility commonly maps both to exit 1, so its
# process exit code is not a sufficient cleanup proof.
if (-not $script:privateMarkerIsWindows -and
    $null -eq ('AgenticCodingSecurityGate.PrivateMarkerPosixSignal' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AgenticCodingSecurityGate
{
    public static class PrivateMarkerPosixSignal
    {
        private const int SIGKILL = 9;
        [DllImport("libc", SetLastError = true)]
        private static extern int kill(int pid, int signal);

        [DllImport("libc", SetLastError = true)]
        private static extern int getpgid(int pid);

        public static bool IsOwnedProcessGroup(
            int ownerProcessId,
            int processGroupId
        )
        {
            return ownerProcessId > 0 &&
                processGroupId > 0 &&
                getpgid(ownerProcessId) == processGroupId;
        }

        public static bool KillOwnedProcessGroup(
            int ownerProcessId,
            int processGroupId
        )
        {
            // group leaderが生存して同じgroupを所有すると確認できる間だけ送る。
            // ESRCHはanchor喪失を示すため、cleanup成功には数えない。
            if (!IsOwnedProcessGroup(ownerProcessId, processGroupId))
            {
                return false;
            }
            int result = kill(-processGroupId, SIGKILL);
            return result == 0;
        }
    }
}
'@
}

# PS5.1のnative process引数はArgumentListを使えないため、Windows規則で安全にquoteする。
function ConvertTo-PrivateMarkerProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    if ([string]::IsNullOrEmpty($Argument)) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    # Windows PowerShell 5.1 lacks ProcessStartInfo.ArgumentList. Apply the
    # C-runtime escaping rules only for that compatibility path.
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            [void]$builder.Append([char]92, (($backslashes * 2) + 1))
            [void]$builder.Append([char]34)
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append([char]92, $backslashes)
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append([char]92, ($backslashes * 2))
    }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

# setup/launch/runtime/cleanupの全phaseが同じoperation時計を参照する。
function Get-PrivateMarkerRemainingMilliseconds {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,

        [Parameter(Mandatory = $true)]
        [long]$DeadlineMilliseconds
    )

    $remaining = $DeadlineMilliseconds - $Stopwatch.ElapsedMilliseconds
    if ($remaining -le 0) {
        return 0
    }
    return [int][Math]::Min([int]::MaxValue, $remaining)
}

function Assert-PrivateMarkerOperationTimeRemaining {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,

        [Parameter(Mandatory = $true)]
        [long]$DeadlineMilliseconds
    )

    if ((Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $Stopwatch `
            -DeadlineMilliseconds $DeadlineMilliseconds) -le 0) {
        throw 'Bounded process operation deadline expired.'
    }
}

function Get-PrivateMarkerCappedRemainingMilliseconds {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,

        [Parameter(Mandatory = $true)]
        [long]$DeadlineMilliseconds,

        [Parameter(Mandatory = $true)]
        [int]$MaximumMilliseconds
    )

    return [Math]::Min(
        $MaximumMilliseconds,
        (Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $Stopwatch `
            -DeadlineMilliseconds $DeadlineMilliseconds)
    )
}

# Windows PowerShell 5.1はredirected stdinのStreamWriterをconsole encodingから
# 作るため、raw BaseStreamへ触る前でもUTF-8 BOMを送ることがある。Process.Start
# の瞬間だけBOMなしencodingへ固定し、callerのconsole状態は必ず復元する。
function Start-PrivateMarkerProcessWithRawInput {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    $restoreConsoleInputEncoding = $false
    $originalConsoleInputEncoding = $null
    if ($script:privateMarkerIsWindows -and
        $Process.StartInfo.RedirectStandardInput -and
        $null -eq $Process.StartInfo.PSObject.Properties[
            'StandardInputEncoding'
        ]) {
        $originalConsoleInputEncoding = [Console]::InputEncoding
        [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
        $restoreConsoleInputEncoding = $true
    }
    try {
        return $Process.Start()
    }
    finally {
        if ($restoreConsoleInputEncoding) {
            [Console]::InputEncoding = $originalConsoleInputEncoding
        }
    }
}

# POSIXでは負のPGIDへsignalを送り、callerと別groupの子孫だけを有限時間で停止する。
function Stop-PrivateMarkerPosixProcessGroupBounded {
    param(
        [int]$OwnerProcessId,
        [int]$ProcessGroupId,
        [int]$WaitMilliseconds = 5000
    )

    # live owner anchorの所属をsignal直前に確認する。ownerがreap済みなら
    # 再利用された同じ数値PGIDへ触れずcleanup failureとして返す。
    return [AgenticCodingSecurityGate.PrivateMarkerPosixSignal]::
        KillOwnedProcessGroup(
        $OwnerProcessId,
        $ProcessGroupId
    )
}

# 自分が所有権を証明できたJob/process groupだけを閉じ、無関係なprocessを殺さない。
function Stop-PrivateMarkerOwnedProcessTreeBounded {
    param(
        [System.Diagnostics.Process]$Process,
        [ref]$WindowsJobHandle,
        [int]$PosixProcessGroupId,
        [int]$WaitMilliseconds = 5000
    )

    if ($WindowsJobHandle.Value -ne [IntPtr]::Zero) {
        $closed = [AgenticCodingSecurityGate.PrivateMarkerJob]::Close(
            $WindowsJobHandle.Value
        )
        $WindowsJobHandle.Value = [IntPtr]::Zero
        if ($WaitMilliseconds -gt 0 -and -not $Process.HasExited) {
            [void]$Process.WaitForExit($WaitMilliseconds)
        }
        return $closed -and $Process.HasExited
    }
    if ($PosixProcessGroupId -gt 0) {
        if ($Process.HasExited) {
            return $false
        }
        $groupStopped = Stop-PrivateMarkerPosixProcessGroupBounded `
            -OwnerProcessId $Process.Id `
            -ProcessGroupId $PosixProcessGroupId `
            -WaitMilliseconds $WaitMilliseconds
        if ($WaitMilliseconds -gt 0 -and -not $Process.HasExited) {
            [void]$Process.WaitForExit($WaitMilliseconds)
        }
        return $groupStopped -and $Process.HasExited
    }
    return Stop-PrivateMarkerProcessTreeBounded `
        -Process $Process `
        -WaitMilliseconds $WaitMilliseconds
}

# containment確立前の失敗時も直下processをboundedに回収する最後の防衛線。
function Stop-PrivateMarkerProcessTreeBounded {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$WaitMilliseconds = 5000
    )

    $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Process.HasExited) {
        return $true
    }

    try {
        $killTreeMethod = $Process.GetType().GetMethod('Kill', [Type[]]@([bool]))
        if ($null -ne $killTreeMethod) {
            [void]$killTreeMethod.Invoke($Process, @($true))
        } elseif ($script:privateMarkerIsWindows) {
            # .NET Framework has no Kill(entireProcessTree). taskkill /T is the
            # bounded Windows fallback and is itself bounded below.
            $taskkillInfo = New-Object System.Diagnostics.ProcessStartInfo
            $taskkillInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            $taskkillInfo.Arguments = "/PID $($Process.Id) /T /F"
            $taskkillInfo.UseShellExecute = $false
            $taskkillInfo.CreateNoWindow = $true
            $taskkillRemaining = Get-PrivateMarkerRemainingMilliseconds `
                -Stopwatch $cleanupStopwatch `
                -DeadlineMilliseconds $WaitMilliseconds
            if ($taskkillRemaining -gt 0) {
                $taskkill = [System.Diagnostics.Process]::Start($taskkillInfo)
                try {
                    $taskkillRemaining = Get-PrivateMarkerRemainingMilliseconds `
                        -Stopwatch $cleanupStopwatch `
                        -DeadlineMilliseconds $WaitMilliseconds
                    if (-not $taskkill.WaitForExit($taskkillRemaining)) {
                        $taskkill.Kill()
                        $taskkillRemaining =
                            Get-PrivateMarkerRemainingMilliseconds `
                                -Stopwatch $cleanupStopwatch `
                                -DeadlineMilliseconds $WaitMilliseconds
                        if ($taskkillRemaining -gt 0) {
                            [void]$taskkill.WaitForExit($taskkillRemaining)
                        }
                    }
                }
                finally {
                    $taskkill.Dispose()
                }
            } else {
                $Process.Kill()
            }
        } else {
            $Process.Kill()
        }
    }
    catch {
        if (-not $Process.HasExited) {
            try { $Process.Kill() } catch { }
        }
    }

    $remaining = Get-PrivateMarkerRemainingMilliseconds `
        -Stopwatch $cleanupStopwatch `
        -DeadlineMilliseconds $WaitMilliseconds
    $processExited = if ($remaining -gt 0) {
        $Process.WaitForExit($remaining)
    } else {
        $Process.HasExited
    }
    if (-not $processExited -and -not $Process.HasExited) {
        try { $Process.Kill() } catch { }
        $remaining = Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $cleanupStopwatch `
            -DeadlineMilliseconds $WaitMilliseconds
        if ($remaining -gt 0) {
            [void]$Process.WaitForExit($remaining)
        }
    }
    return $Process.HasExited
}

# Windows atomic launcher専用のstream pump。全pipeをraw byteのまま同一deadlineで進める。
function Complete-PrivateMarkerAtomicStreams {
    param(
        [System.IO.Stream[]]$Streams,
        [System.Threading.Tasks.Task[]]$Tasks,
        [int]$WaitMilliseconds = 1000
    )

    $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # child tree 停止後も pipe を継承した descendant が残る場合がある。まず
    # EOF を有限時間待ち、残った parent endpoint を閉じてから task 完了を
    # もう一度有限時間で確認する。未完了 task を残したまま return しない。
    $pending = @($Tasks | Where-Object {
        $null -ne $_ -and -not $_.IsCompleted
    })
    if ($pending.Count -gt 0) {
        $remaining = Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $cleanupStopwatch `
            -DeadlineMilliseconds $WaitMilliseconds
        if ($remaining -gt 0) {
            try {
                [void][System.Threading.Tasks.Task]::WaitAll(
                    [System.Threading.Tasks.Task[]]$pending,
                    $remaining)
            }
            catch {
                # fault/cancel も task 完了状態である。下の IsCompleted で判定する。
            }
        }
    }

    $pending = @($Tasks | Where-Object {
        $null -ne $_ -and -not $_.IsCompleted
    })
    if ($pending.Count -gt 0) {
        foreach ($stream in $Streams) {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        $remaining = Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $cleanupStopwatch `
            -DeadlineMilliseconds $WaitMilliseconds
        if ($remaining -gt 0) {
            try {
                [void][System.Threading.Tasks.Task]::WaitAll(
                    [System.Threading.Tasks.Task[]]$pending,
                    $remaining)
            }
            catch {
                # endpoint close に伴う fault/cancel は許容するが、未完了は拒否する。
            }
        }
    }

    $streamsCompleted = @($Tasks | Where-Object {
            $null -ne $_ -and -not $_.IsCompleted
        }).Count -eq 0
    return $streamsCompleted
}

# Job close失敗でもowned handleを保持したままJob/direct childの順に停止し、
# direct childの終了を有限時間で確認する。全cleanup failureはまとめて返す。
function Stop-PrivateMarkerAtomicWindowsChild {
    param(
        [Parameter(Mandatory = $true)]
        [AgenticSecurityGateContainedProcess]$NativeChild,

        [int]$WaitMilliseconds = 5000
    )

    $cleanupFailures = New-Object System.Collections.Generic.List[Exception]
    $jobCloseFailed = $false
    $childExited = $false
    try {
        $NativeChild.CloseJob()
    }
    catch {
        $jobCloseFailed = $true
        $cleanupFailures.Add($_.Exception) | Out-Null
    }

    if ($jobCloseFailed) {
        try {
            $NativeChild.TerminateDirectProcess()
        }
        catch {
            $cleanupFailures.Add($_.Exception) | Out-Null
        }
    }

    try {
        $childExited = if ($NativeChild.HasExited) {
            $true
        } elseif ($WaitMilliseconds -gt 0) {
            $NativeChild.WaitForExit($WaitMilliseconds)
        } else {
            $false
        }
    }
    catch {
        $cleanupFailures.Add($_.Exception) | Out-Null
    }

    if ($cleanupFailures.Count -eq 1) {
        throw $cleanupFailures[0]
    }
    if ($cleanupFailures.Count -gt 1) {
        throw [AggregateException]::new(
            'Contained child cleanup failed.',
            [Exception[]]$cleanupFailures.ToArray()
        )
    }
    return $childExited
}

function Invoke-PrivateMarkerAtomicWindowsProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [hashtable]$Environment,
        [string]$WorkingDirectory = '',
        [byte[]]$StandardInputBytes = @(),
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$OperationStopwatch,
        [Parameter(Mandatory = $true)]
        [long]$OperationDeadlineMilliseconds,
        [Parameter(Mandatory = $true)]
        [long]$ExecutionDeadlineMilliseconds,
        [int]$DrainTimeoutMilliseconds = 5000,
        [int]$MaxStandardOutputBytes = (4 * 1024 * 1024),
        [int]$MaxStandardErrorBytes = (1024 * 1024),
        [ValidateSet('', 'assign', 'resume', 'close', 'dispose')]
        [string]$ForceWindowsLaunchFailure = ''
    )

    # PowerShellは空byte[]をparameter binding時に`$null`へunrollし得る。
    if ($null -eq $StandardInputBytes) {
        $StandardInputBytes = New-Object byte[] 0
    }
    Assert-PrivateMarkerOperationTimeRemaining `
        -Stopwatch $OperationStopwatch `
        -DeadlineMilliseconds $ExecutionDeadlineMilliseconds

    $process = $null
    $nativeChild = $null
    $stdinStream = $null
    $stdoutStream = $null
    $stderrStream = $null
    $stdoutBuffer = New-Object System.IO.MemoryStream
    $stderrBuffer = New-Object System.IO.MemoryStream
    $processStarted = $false
    $stdinTask = $null
    $stdoutTask = $null
    $stderrTask = $null
    $treeStopped = $true
    $streamsDrained = $true
    try {
        if ($script:privateMarkerIsWindows) {
            try {
                $launchCleanupMilliseconds =
                    Get-PrivateMarkerRemainingMilliseconds `
                        -Stopwatch $OperationStopwatch `
                        -DeadlineMilliseconds $OperationDeadlineMilliseconds
                $launchExecutionMilliseconds =
                    Get-PrivateMarkerRemainingMilliseconds `
                        -Stopwatch $OperationStopwatch `
                        -DeadlineMilliseconds $ExecutionDeadlineMilliseconds
                $nativeChild = [AgenticSecurityGateContainedProcess]::StartContained(
                    $FilePath,
                    [string[]]$ArgumentList,
                    $Environment,
                    $WorkingDirectory,
                    $ForceWindowsLaunchFailure,
                    $launchExecutionMilliseconds,
                    $launchCleanupMilliseconds)
                $stdinStream = $nativeChild.StandardInput
                $stdoutStream = $nativeChild.StandardOutput
                $stderrStream = $nativeChild.StandardError
            }
            catch {
                throw 'child-process-containment-unavailable'
            }
        } else {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $FilePath
            if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
                foreach ($argument in $ArgumentList) {
                    $startInfo.ArgumentList.Add([string]$argument)
                }
            } else {
                $startInfo.Arguments = (($ArgumentList | ForEach-Object {
                    ConvertTo-PrivateMarkerProcessArgument -Argument ([string]$_)
                }) -join ' ')
            }
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            if ($null -ne $startInfo.PSObject.Properties[
                'StandardInputEncoding'
            ]) {
                $startInfo.StandardInputEncoding =
                    [Text.UTF8Encoding]::new($false)
            }
            $startInfo.EnvironmentVariables.Clear()
            foreach ($entry in $Environment.GetEnumerator()) {
                $startInfo.EnvironmentVariables[[string]$entry.Key] =
                    [string]$entry.Value
            }
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            Assert-PrivateMarkerOperationTimeRemaining `
                -Stopwatch $OperationStopwatch `
                -DeadlineMilliseconds $ExecutionDeadlineMilliseconds
            [void](Start-PrivateMarkerProcessWithRawInput -Process $process)
            $stdinStream = $process.StandardInput.BaseStream
            $stdoutStream = $process.StandardOutput.BaseStream
            $stderrStream = $process.StandardError.BaseStream
        }
        $processStarted = $true

        # stdin write と stdout/stderr read を同時に進め、batch input/output の
        # pipe backpressure で相互待ちしない。全taskが同じdeadlineを共有する。
        $stdinClosed = $StandardInputBytes.Length -eq 0
        if ($stdinClosed) {
            $stdinStream.Dispose()
        } else {
            $stdinTask = $stdinStream.WriteAsync(
                $StandardInputBytes, 0, $StandardInputBytes.Length)
        }
        $stdoutChunk = New-Object byte[] 8192
        $stderrChunk = New-Object byte[] 8192
        $stdoutTask = $stdoutStream.ReadAsync(
            $stdoutChunk, 0, $stdoutChunk.Length)
        $stderrTask = $stderrStream.ReadAsync(
            $stderrChunk, 0, $stderrChunk.Length)
        $stdoutClosed = $false
        $stderrClosed = $false
        $limitExceeded = ''
        $jobClosedAfterParentExit = $false

        while ((-not $stdinClosed -or -not $stdoutClosed -or
                -not $stderrClosed) -and
            [string]::IsNullOrEmpty($limitExceeded) -and
            $OperationStopwatch.ElapsedMilliseconds -lt
                $ExecutionDeadlineMilliseconds) {
            $pendingTasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]
            if (-not $stdoutClosed) {
                $pendingTasks.Add($stdoutTask)
            }
            if (-not $stderrClosed) {
                $pendingTasks.Add($stderrTask)
            }
            if (-not $stdinClosed) {
                $pendingTasks.Add($stdinTask)
            }
            $remaining = Get-PrivateMarkerRemainingMilliseconds `
                -Stopwatch $OperationStopwatch `
                -DeadlineMilliseconds $ExecutionDeadlineMilliseconds
            if ($remaining -le 0) {
                break
            }
            [void][System.Threading.Tasks.Task]::WaitAny(
                $pendingTasks.ToArray(),
                [Math]::Min(100, $remaining))

            if (-not $stdoutClosed -and $stdoutTask.IsCompleted) {
                try {
                    $count = $stdoutTask.GetAwaiter().GetResult()
                }
                catch {
                    throw 'Child process stdout read failed.'
                }
                if ($count -eq 0) {
                    $stdoutClosed = $true
                } elseif (($stdoutBuffer.Length + $count) -gt $MaxStandardOutputBytes) {
                    $limitExceeded = 'stdout'
                } else {
                    $stdoutBuffer.Write($stdoutChunk, 0, $count)
                    $stdoutTask = $stdoutStream.ReadAsync(
                        $stdoutChunk, 0, $stdoutChunk.Length)
                }
            }

            if (-not $stderrClosed -and $stderrTask.IsCompleted) {
                try {
                    $count = $stderrTask.GetAwaiter().GetResult()
                }
                catch {
                    throw 'Child process stderr read failed.'
                }
                if ($count -eq 0) {
                    $stderrClosed = $true
                } elseif (($stderrBuffer.Length + $count) -gt $MaxStandardErrorBytes) {
                    $limitExceeded = 'stderr'
                } else {
                    $stderrBuffer.Write($stderrChunk, 0, $count)
                    $stderrTask = $stderrStream.ReadAsync(
                        $stderrChunk, 0, $stderrChunk.Length)
                }
            }

            if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                try {
                    [void]$stdinTask.GetAwaiter().GetResult()
                }
                catch {
                    throw 'Child process stdin write failed.'
                }
                $stdinStream.Dispose()
                $stdinClosed = $true
            }

            # direct childが先に終了してもpipeを握る孫をdeadlineまで放置しない。
            # Jobを即時closeし、残るasync readは下のbounded drainで回収する。
            if ($null -ne $nativeChild -and
                -not $jobClosedAfterParentExit -and
                $nativeChild.HasExited -and
                (-not $stdoutClosed -or -not $stderrClosed)) {
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $OperationStopwatch `
                        -DeadlineMilliseconds $OperationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped =
                    (Stop-PrivateMarkerAtomicWindowsChild `
                        -NativeChild $nativeChild `
                        -WaitMilliseconds $cleanupWait) -and $treeStopped
                $jobClosedAfterParentExit = $true
            }
        }

        $remaining = Get-PrivateMarkerRemainingMilliseconds `
            -Stopwatch $OperationStopwatch `
            -DeadlineMilliseconds $ExecutionDeadlineMilliseconds
        $streamsCompleted = $stdinClosed -and $stdoutClosed -and $stderrClosed
        $processExited = $false
        if ($streamsCompleted -and [string]::IsNullOrEmpty($limitExceeded)) {
            $processExited = if ($remaining -le 0) {
                if ($null -ne $nativeChild) {
                    $nativeChild.HasExited
                } else {
                    $process.HasExited
                }
            } elseif ($null -ne $nativeChild) {
                $nativeChild.WaitForExit($remaining)
            } else {
                $process.WaitForExit($remaining)
            }
        }
        $timedOut = (
            [string]::IsNullOrEmpty($limitExceeded) -and
            -not ($streamsCompleted -and $processExited))
        if ($timedOut -or -not [string]::IsNullOrEmpty($limitExceeded)) {
            $cleanupWait =
                Get-PrivateMarkerCappedRemainingMilliseconds `
                    -Stopwatch $OperationStopwatch `
                    -DeadlineMilliseconds $OperationDeadlineMilliseconds `
                    -MaximumMilliseconds $DrainTimeoutMilliseconds
            if ($null -ne $nativeChild) {
                $treeStopped =
                    (Stop-PrivateMarkerAtomicWindowsChild `
                        -NativeChild $nativeChild `
                        -WaitMilliseconds $cleanupWait) -and $treeStopped
            } elseif (-not $process.HasExited) {
                $treeStopped =
                    (Stop-PrivateMarkerProcessTreeBounded `
                        -Process $process `
                        -WaitMilliseconds $cleanupWait) -and $treeStopped
            }
            $cleanupWait =
                Get-PrivateMarkerCappedRemainingMilliseconds `
                    -Stopwatch $OperationStopwatch `
                    -DeadlineMilliseconds $OperationDeadlineMilliseconds `
                    -MaximumMilliseconds $DrainTimeoutMilliseconds
            $streamsDrained =
                (Complete-PrivateMarkerAtomicStreams `
                    -Streams @($stdinStream, $stdoutStream, $stderrStream) `
                    -Tasks @($stdinTask, $stdoutTask, $stderrTask) `
                    -WaitMilliseconds $cleanupWait) -and $streamsDrained
        }

        [byte[]]$stdoutBytes = @()
        [byte[]]$stderrBytes = @()
        if (-not $timedOut -and [string]::IsNullOrEmpty($limitExceeded)) {
            $stdoutBytes = $stdoutBuffer.ToArray()
            $stderrBytes = $stderrBuffer.ToArray()
        }
        return [pscustomobject]@{
            ExitCode = if ($timedOut -or -not [string]::IsNullOrEmpty($limitExceeded)) {
                -1
            } elseif ($null -ne $nativeChild) {
                $nativeChild.ExitCode
            } else {
                $process.ExitCode
            }
            StandardOutputBytes = $stdoutBytes
            StandardErrorBytes = $stderrBytes
            TimedOut = $timedOut
            OutputLimitExceeded = $limitExceeded
            TreeStopped = $treeStopped
            StreamsDrained = $streamsDrained
        }
    }
    catch {
        $originalFailure = $_
        $cleanupFailure = $null
        if ($processStarted) {
            try {
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $OperationStopwatch `
                        -DeadlineMilliseconds $OperationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                if ($null -ne $nativeChild) {
                    [void](Stop-PrivateMarkerAtomicWindowsChild `
                        -NativeChild $nativeChild `
                        -WaitMilliseconds $cleanupWait)
                } elseif (-not $process.HasExited) {
                    [void](Stop-PrivateMarkerProcessTreeBounded `
                        -Process $process `
                        -WaitMilliseconds $cleanupWait)
                }
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $OperationStopwatch `
                        -DeadlineMilliseconds $OperationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                [void](Complete-PrivateMarkerAtomicStreams `
                    -Streams @($stdinStream, $stdoutStream, $stderrStream) `
                    -Tasks @($stdinTask, $stdoutTask, $stderrTask) `
                    -WaitMilliseconds $cleanupWait)
            }
            catch {
                $cleanupFailure = $_
            }
        }
        if ($null -ne $cleanupFailure) {
            throw [AggregateException]::new(
                'Contained child execution and cleanup failed.',
                [Exception[]]@(
                    $originalFailure.Exception,
                    $cleanupFailure.Exception
                )
            )
        }
        throw $originalFailure
    }
    finally {
        $stdoutBuffer.Dispose()
        $stderrBuffer.Dispose()
        if ($null -ne $nativeChild) {
            $nativeChild.Dispose()
        } elseif ($null -ne $process) {
            if ($null -ne $stdinStream) { $stdinStream.Dispose() }
            if ($null -ne $stdoutStream) { $stdoutStream.Dispose() }
            if ($null -ne $stderrStream) { $stderrStream.Dispose() }
            $process.Dispose()
        }
    }
}

# 子processへ渡す環境は親processのcloneから削る方式にしない。将来追加される
# loader/runtime/credential変数を取りこぼさないよう、空のmapへ必要値だけを足す。
function New-PrivateMarkerChildEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IsolationRoot,

        [hashtable]$RequestedEnvironment = @{},

        [switch]$PassThroughGitEnvironment,

        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$OperationStopwatch,

        [Parameter(Mandatory = $true)]
        [long]$OperationDeadlineMilliseconds,

        [string]$OwnedWindowsJobMarkerName =
            'AGENTIC_CODING_SECURITY_GATE_OWNED_WINDOWS_JOB'
    )

    $environment = @{}
    $homeDirectory = Join-Path $IsolationRoot 'home'
    $xdgDirectory = Join-Path $IsolationRoot 'xdg'
    $temporaryDirectory = Join-Path $IsolationRoot 'tmp'
    $cacheDirectory = Join-Path $IsolationRoot 'cache'
    $dataDirectory = Join-Path $IsolationRoot 'data'
    $templateDirectory = Join-Path $IsolationRoot 'empty-template'
    $hooksDirectory = Join-Path $IsolationRoot 'empty-hooks'
    foreach ($directory in @(
        $homeDirectory,
        $xdgDirectory,
        $temporaryDirectory,
        $cacheDirectory,
        $dataDirectory,
        $templateDirectory,
        $hooksDirectory
    )) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $OperationStopwatch `
            -DeadlineMilliseconds $OperationDeadlineMilliseconds
    }

    # OS loaderが必要とする値もambient値を信用せず、runtime APIと隔離rootから導出する。
    if ($script:privateMarkerIsWindows) {
        $systemDirectory = [Environment]::SystemDirectory
        if ([string]::IsNullOrWhiteSpace($systemDirectory) -or
            -not [IO.Path]::IsPathRooted($systemDirectory)) {
            throw 'Trusted Windows system directory could not be resolved.'
        }
        $systemRoot = [IO.Directory]::GetParent($systemDirectory).FullName
        $systemDriveRoot = [IO.Path]::GetPathRoot($systemRoot)
        if ([string]::IsNullOrWhiteSpace($systemDriveRoot)) {
            throw 'Trusted Windows system drive could not be resolved.'
        }
        $systemDrive = $systemDriveRoot.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $programData = [IO.Path]::Combine($systemDriveRoot, 'ProgramData')
        $environment['SystemRoot'] = $systemRoot
        $environment['WINDIR'] = $systemRoot
        # PowerShell/.NET の known-folder 解決が未展開の `%SystemDrive%` を cwd
        # 配下へ作らないよう、OS root から導出した非ambient値だけを渡す。
        $environment['SystemDrive'] = $systemDrive
        $environment['ProgramData'] = $programData
        $environment['TEMP'] = $temporaryDirectory
        $environment['TMP'] = $temporaryDirectory
        # Windows command discovery needs PATHEXT even when PATH itself is a
        # test-only single trusted directory. Value is a fixed OS convention.
        $environment['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'
        $environment[$OwnedWindowsJobMarkerName] = '1'
    } else {
        $environment['TMPDIR'] = $temporaryDirectory
        $environment['LANG'] = 'C'
        $environment['LC_ALL'] = 'C'
    }

    $environment['HOME'] = $homeDirectory
    $environment['USERPROFILE'] = $homeDirectory
    $environment['XDG_CONFIG_HOME'] = $xdgDirectory
    $environment['XDG_CACHE_HOME'] = $cacheDirectory
    $environment['XDG_DATA_HOME'] = $dataDirectory
    $environment['PSModulePath'] = Join-Path $PSHOME 'Modules'
    $environment['DOTNET_EnableDiagnostics'] = '0'
    $environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $environment['POWERSHELL_TELEMETRY_OPTOUT'] = '1'
    $environment['POWERSHELL_UPDATECHECK'] = 'Off'

    # scanner entrypointの境界testだけは明示されたGIT_*と、親testがnative
    # Gitの絶対pathから作った単一PATHを受け取る。ambient loader/runtime/
    # shell/credential/cloud変数はrequested mapにあっても渡さない。
    if ($PassThroughGitEnvironment) {
        foreach ($nameObject in $RequestedEnvironment.Keys) {
            $name = [string]$nameObject
            if ($name.StartsWith(
                'GIT_',
                [StringComparison]::OrdinalIgnoreCase
            ) -or [string]::Equals(
                $name,
                'PATH',
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $environment[$name] = [string]$RequestedEnvironment[$nameObject]
            }
            Assert-PrivateMarkerOperationTimeRemaining `
                -Stopwatch $OperationStopwatch `
                -DeadlineMilliseconds $OperationDeadlineMilliseconds
        }
        return $environment
    }

    $emptyGlobalConfig = Join-Path $IsolationRoot 'empty-global.gitconfig'
    $emptySystemConfig = Join-Path $IsolationRoot 'empty-system.gitconfig'
    $emptyAttributes = Join-Path $IsolationRoot 'empty-attributes'
    $emptyExcludes = Join-Path $IsolationRoot 'empty-excludes'
    foreach ($emptyFile in @(
        $emptyGlobalConfig,
        $emptySystemConfig,
        $emptyAttributes,
        $emptyExcludes
    )) {
        if (-not (Test-Path -LiteralPath $emptyFile -PathType Leaf)) {
            [IO.File]::WriteAllText(
                $emptyFile,
                '',
                [Text.UTF8Encoding]::new($false)
            )
        }
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $OperationStopwatch `
            -DeadlineMilliseconds $OperationDeadlineMilliseconds
    }

    # Gitの制御面もallowlistで再構成し、protocol、hook、attribute、exclude、
    # template、fsmonitor、lazy fetchを外部設定から起動できないよう固定する。
    $environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $environment['GIT_ATTR_NOSYSTEM'] = '1'
    $environment['GIT_CONFIG_GLOBAL'] =
        $emptyGlobalConfig.Replace([string][char]92, '/')
    $environment['GIT_CONFIG_SYSTEM'] =
        $emptySystemConfig.Replace([string][char]92, '/')
    $environment['GIT_TERMINAL_PROMPT'] = '0'
    $environment['GIT_LFS_SKIP_SMUDGE'] = '1'
    $environment['GIT_OPTIONAL_LOCKS'] = '0'
    $environment['GIT_NO_REPLACE_OBJECTS'] = '1'
    $environment['GIT_NO_LAZY_FETCH'] = '1'

    $safeConfig = @(
        [pscustomobject]@{
            Key = 'core.hooksPath'
            Value = $hooksDirectory.Replace([string][char]92, '/')
        },
        [pscustomobject]@{
            Key = 'core.attributesFile'
            Value = $emptyAttributes.Replace([string][char]92, '/')
        },
        [pscustomobject]@{
            Key = 'core.excludesFile'
            Value = $emptyExcludes.Replace([string][char]92, '/')
        },
        [pscustomobject]@{ Key = 'core.fsmonitor'; Value = 'false' },
        [pscustomobject]@{ Key = 'protocol.allow'; Value = 'never' },
        [pscustomobject]@{ Key = 'submodule.recurse'; Value = 'false' },
        [pscustomobject]@{
            Key = 'init.templateDir'
            Value = $templateDirectory.Replace([string][char]92, '/')
        }
    )
    $environment['GIT_CONFIG_COUNT'] = [string]$safeConfig.Count
    for ($index = 0; $index -lt $safeConfig.Count; $index++) {
        $environment["GIT_CONFIG_KEY_$index"] = $safeConfig[$index].Key
        $environment["GIT_CONFIG_VALUE_$index"] = $safeConfig[$index].Value
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $OperationStopwatch `
            -DeadlineMilliseconds $OperationDeadlineMilliseconds
    }
    return $environment
}

# child-only環境、出力量、deadline、tree cleanupを1か所で強制するprocess境界。
function Invoke-PrivateMarkerBoundedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$IsolationRoot,

        [string]$WorkingDirectory = '',

        [hashtable]$InheritedEnvironment = @{},

        [AllowNull()]
        [byte[]]$StandardInputBytes = $null,

        [int]$MaxStdinBytes = 1048576,

        [int]$TimeoutMilliseconds = 30000,

        # Native child output is untrusted. Bound both streams independently so
        # a corrupted repository, fake executable, or noisy failure cannot grow
        # the scanner process without limit.
        [int]$MaxStdoutBytes = 16777216,

        [int]$MaxStderrBytes = 1048576,

        [int]$DrainTimeoutMilliseconds = 5000,

        # Test-only selector for the portable libc setsid gate. Production
        # POSIX calls use it automatically when an external setsid is absent.
        [switch]$ForceNativePosixSessionGate,

        # Self-test専用。setupがoperation deadlineへ計上されることを実測する。
        [int]$ForceSetupDelayMilliseconds = 0,

        # Self-test専用。setsid後/readiness公開前の遅延中も親のdeadlineで停止する。
        [int]$ForceNativePosixReadyDelayMilliseconds = 0,

        # Use only when testing the public scanner entrypoint. The scanner must
        # receive the hostile parent environment and isolate its own Git child.
        [switch]$PassThroughGitEnvironment,

        # Self-test専用。launch/Job close/Dispose failureでもowned targetを
        # 残さず、terminate/retry/waitをboundedに完了させる。
        [ValidateSet('', 'assign', 'resume', 'close', 'dispose')]
        [string]$ForceWindowsLaunchFailure = ''
    )

    $operationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($TimeoutMilliseconds -le 0 -or
        $MaxStdinBytes -lt 0 -or
        $MaxStdoutBytes -lt 0 -or
        $MaxStderrBytes -lt 0 -or
        $DrainTimeoutMilliseconds -le 0 -or
        $ForceSetupDelayMilliseconds -lt 0 -or
        $ForceNativePosixReadyDelayMilliseconds -lt 0) {
        throw 'Bounded process limits must be positive (output limits may be zero).'
    }
    $operationDeadlineMilliseconds = [long]$TimeoutMilliseconds
    # timeout直前までtargetを走らせるとcleanup確認の余地が残らない。短い
    # operationでは半分、長いoperationでは最大250msだけを同じhard deadline内に確保する。
    $cleanupReserveMilliseconds = if ($TimeoutMilliseconds -gt 1) {
        [long][Math]::Min(
            250,
            [Math]::Min(
                $TimeoutMilliseconds - 1,
                [Math]::Max(
                    1,
                    [Math]::Ceiling($TimeoutMilliseconds * 0.5)
                )
            )
        )
    } else {
        0L
    }
    $executionDeadlineMilliseconds =
        $operationDeadlineMilliseconds - $cleanupReserveMilliseconds

    if ($ForceSetupDelayMilliseconds -gt 0) {
        $setupDelay = [Math]::Min(
            $ForceSetupDelayMilliseconds,
            (Get-PrivateMarkerRemainingMilliseconds `
                -Stopwatch $operationStopwatch `
                -DeadlineMilliseconds $operationDeadlineMilliseconds)
        )
        if ($setupDelay -gt 0) {
            Start-Sleep -Milliseconds $setupDelay
        }
    }
    Assert-PrivateMarkerOperationTimeRemaining `
        -Stopwatch $operationStopwatch `
        -DeadlineMilliseconds $operationDeadlineMilliseconds
    if ($null -ne $StandardInputBytes -and
        $StandardInputBytes.Length -gt $MaxStdinBytes) {
        throw 'Bounded process standard input exceeds the configured byte limit.'
    }

    $ownedJobMarkerName =
        'AGENTIC_CODING_SECURITY_GATE_OWNED_WINDOWS_JOB'
    $reuseOwnedWindowsJob = $false
    if ($script:privateMarkerIsWindows -and
        [Environment]::GetEnvironmentVariable($ownedJobMarkerName) -eq '1') {
        $reuseOwnedWindowsJob =
            [AgenticCodingSecurityGate.PrivateMarkerJob]::
                IsCurrentProcessInOwnedJob()
    }
    Assert-PrivateMarkerOperationTimeRemaining `
        -Stopwatch $operationStopwatch `
        -DeadlineMilliseconds $operationDeadlineMilliseconds

    $effectiveFileName = $FileName
    $effectiveArguments = @($Arguments)
    $useAtomicWindowsContainment =
        $script:privateMarkerIsWindows -and -not $reuseOwnedWindowsJob
    $usePosixProcessGroup = $false
    $useNativePosixSessionGate = $false
    $posixGateReadyPath = $null
    $posixGateReleasePath = $null
    $posixGateExitPath = $null
    if (-not $script:privateMarkerIsWindows) {
        $setsidPath = @('/usr/bin/setsid', '/bin/setsid') |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        $createSessionInsideWrapper =
            $ForceNativePosixSessionGate -or
            [string]::IsNullOrWhiteSpace($setsidPath)

        # external setsidでもtargetへ直結しない。共通anchor wrapperがreadiness、
        # target exit status、group ownershipを保持し、親がgroupを止めるまで生存する。
        $usePosixProcessGroup = $true
        $useNativePosixSessionGate = $true
        $gateId = [Guid]::NewGuid().ToString('N')
        $posixGateReadyPath = Join-Path `
            $IsolationRoot `
            "posix-session-ready-$gateId"
        $posixGateReleasePath = Join-Path `
            $IsolationRoot `
            "posix-session-release-$gateId"
        $posixGateExitPath = Join-Path `
            $IsolationRoot `
            "posix-session-exit-$gateId"
        $payloadJson = [pscustomobject]@{
            FileName = $FileName
            Arguments = @($Arguments)
        } | ConvertTo-Json -Compress -Depth 4
        $payloadBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($payloadJson)
        )
        $readyPathBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($posixGateReadyPath)
        )
        $releasePathBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($posixGateReleasePath)
        )
        $exitPathBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($posixGateExitPath)
        )
        $anchorDeadlineMilliseconds = [long]$TimeoutMilliseconds +
            [Math]::Max(1000, $DrainTimeoutMilliseconds)
        $posixWrapperTemplate = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$gateStopwatch = [Diagnostics.Stopwatch]::StartNew()
$gateDeadlineMilliseconds = [long]__GATE_TIMEOUT_MS__
$anchorDeadlineMilliseconds = [long]__ANCHOR_TIMEOUT_MS__
$sessionEstablished = $false
$exitPath = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String('__EXIT_PATH__')
)
if ($null -eq ('AgenticCodingSecurityGate.PrivateMarkerPosixSession' -as [type])) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

namespace AgenticCodingSecurityGate
{
    public static class PrivateMarkerPosixSession
    {
        [DllImport("libc", SetLastError = true)]
        private static extern int setsid();

        [DllImport("libc", SetLastError = true)]
        private static extern int getpid();

        [DllImport("libc", SetLastError = true)]
        private static extern int getpgrp();

        public static bool Establish(bool createSession)
        {
            if (createSession && setsid() < 0)
            {
                return false;
            }
            int processId = getpid();
            return processId > 0 && getpgrp() == processId;
        }
    }
}
"@
}

# target終了後もanchorは自発的にreap可能な状態へ移らない。statusをatomicに
# 公開してから、親がowned groupへSIGKILLを送るまで有限時間だけ保持する。
function Publish-TargetExitAndHold {
    param([int]$ExitCode)

    $temporaryExitPath = "$exitPath.tmp"
    try {
        $statusBytes = [Text.Encoding]::ASCII.GetBytes(
            $ExitCode.ToString([Globalization.CultureInfo]::InvariantCulture)
        )
        $statusStream = [IO.FileStream]::new(
            $temporaryExitPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $statusStream.Write($statusBytes, 0, $statusBytes.Length)
            $statusStream.Flush($true)
        }
        finally {
            $statusStream.Dispose()
        }
        [IO.File]::Move($temporaryExitPath, $exitPath)
    }
    catch {
        # status公開失敗でもanchorを失わない。親のdeadline/group cleanupへ委ねる。
        [Console]::Error.WriteLine('Bounded target status publication failed.')
    }
    while ($gateStopwatch.ElapsedMilliseconds -lt $anchorDeadlineMilliseconds) {
        $anchorRemaining = [Math]::Max(
            0,
            $anchorDeadlineMilliseconds - $gateStopwatch.ElapsedMilliseconds
        )
        if ($anchorRemaining -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Min(10, $anchorRemaining))
        }
    }
    exit 125
}

try {
    $createSession = [bool]([int]__CREATE_SESSION__)
    if (-not [AgenticCodingSecurityGate.PrivateMarkerPosixSession]::Establish(
        $createSession
    )) {
        [Console]::Error.WriteLine('Bounded POSIX session setup failed.')
        exit 126
    }
    $sessionEstablished = $true
    $readyPath = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String('__READY_PATH__')
    )
    $releasePath = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String('__RELEASE_PATH__')
    )
    $readyDelayMilliseconds = [int]__READY_DELAY_MS__
    if ($readyDelayMilliseconds -gt 0) {
        $readyDelayRemaining = [Math]::Max(
            0,
            $gateDeadlineMilliseconds - $gateStopwatch.ElapsedMilliseconds
        )
        if ($readyDelayRemaining -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Min(
                $readyDelayMilliseconds,
                $readyDelayRemaining
            ))
        }
    }
    if ($gateStopwatch.ElapsedMilliseconds -ge $gateDeadlineMilliseconds) {
        Publish-TargetExitAndHold -ExitCode 124
    }
    [IO.File]::WriteAllText(
        $readyPath,
        'ready',
        [Text.UTF8Encoding]::new($false)
    )
    $released = $false
    while ($gateStopwatch.ElapsedMilliseconds -lt $gateDeadlineMilliseconds) {
        if ([IO.File]::Exists($releasePath)) {
            $released = $true
            break
        }
        $releaseRemaining = [Math]::Max(
            0,
            $gateDeadlineMilliseconds - $gateStopwatch.ElapsedMilliseconds
        )
        if ($releaseRemaining -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Min(10, $releaseRemaining))
        }
    }
    if (-not $released) {
        Publish-TargetExitAndHold -ExitCode 124
    }
    $payloadJson = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String('__PAYLOAD__')
    )
    $payload = ConvertFrom-Json -InputObject $payloadJson
    $invokeArguments = @($payload.Arguments | ForEach-Object { [string]$_ })
    & ([string]$payload.FileName) @invokeArguments
    $childExitCode = $LASTEXITCODE
    if ($null -eq $childExitCode) {
        $childExitCode = 0
    }
    Publish-TargetExitAndHold -ExitCode ([int]$childExitCode)
}
catch {
    [Console]::Error.WriteLine('Bounded child launch failed.')
    if ($sessionEstablished) {
        Publish-TargetExitAndHold -ExitCode 127
    }
    exit 127
}
'@
        $posixWrapperScript = $posixWrapperTemplate.Replace(
            '__READY_PATH__',
            $readyPathBase64
        ).Replace(
            '__RELEASE_PATH__',
            $releasePathBase64
        ).Replace(
            '__EXIT_PATH__',
            $exitPathBase64
        ).Replace(
            '__PAYLOAD__',
            $payloadBase64
        ).Replace(
            '__READY_DELAY_MS__',
            $ForceNativePosixReadyDelayMilliseconds.ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
        ).Replace(
            '__GATE_TIMEOUT_MS__',
            $TimeoutMilliseconds.ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
        ).Replace(
            '__ANCHOR_TIMEOUT_MS__',
            $anchorDeadlineMilliseconds.ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
        ).Replace(
            '__CREATE_SESSION__',
            $(if ($createSessionInsideWrapper) { '1' } else { '0' })
        )
        $posixWrapperBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($posixWrapperScript)
        )
        $powerShellPath = (
            [Diagnostics.Process]::GetCurrentProcess()
        ).MainModule.FileName
        if ($createSessionInsideWrapper) {
            $effectiveFileName = $powerShellPath
            $effectiveArguments = @(
                '-NoProfile',
                '-EncodedCommand',
                $posixWrapperBase64
            )
        } else {
            $effectiveFileName = $setsidPath
            $effectiveArguments = @(
                '--',
                $powerShellPath,
                '-NoProfile',
                '-EncodedCommand',
                $posixWrapperBase64
            )
        }
    }
    Assert-PrivateMarkerOperationTimeRemaining `
        -Stopwatch $operationStopwatch `
        -DeadlineMilliseconds $operationDeadlineMilliseconds

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $effectiveFileName
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $null -ne $StandardInputBytes
    if ($null -ne $StandardInputBytes -and
        $null -ne $startInfo.PSObject.Properties[
            'StandardInputEncoding'
        ]) {
        $startInfo.StandardInputEncoding =
            [Text.UTF8Encoding]::new($false)
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $argumentListProperty = $startInfo.PSObject.Properties['ArgumentList']
    if ($null -ne $argumentListProperty) {
        foreach ($argument in $effectiveArguments) {
            $startInfo.ArgumentList.Add($argument)
            Assert-PrivateMarkerOperationTimeRemaining `
                -Stopwatch $operationStopwatch `
                -DeadlineMilliseconds $operationDeadlineMilliseconds
        }
    } else {
        $startInfo.Arguments = (
            $effectiveArguments | ForEach-Object {
                ConvertTo-PrivateMarkerProcessArgument -Argument $_
            }
        ) -join ' '
    }

    # ProcessStartInfoは親環境を初期値として持つため必ず全消去し、上の固定
    # allowlistだけを複製する。親process自体の環境は変更しない。
    $allowedChildEnvironment = New-PrivateMarkerChildEnvironment `
        -IsolationRoot $IsolationRoot `
        -RequestedEnvironment $InheritedEnvironment `
        -PassThroughGitEnvironment:$PassThroughGitEnvironment `
        -OperationStopwatch $operationStopwatch `
        -OperationDeadlineMilliseconds $operationDeadlineMilliseconds `
        -OwnedWindowsJobMarkerName $ownedJobMarkerName
    $childEnvironment = $startInfo.EnvironmentVariables
    $childEnvironment.Clear()
    foreach ($name in $allowedChildEnvironment.Keys) {
        $childEnvironment["$name"] = [string]$allowedChildEnvironment[$name]
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $operationStopwatch `
            -DeadlineMilliseconds $operationDeadlineMilliseconds
    }

    if ($useAtomicWindowsContainment) {
        # StringDictionaryをplain hashtableへ写し、C#へcaller-owned objectを渡さない。
        $atomicEnvironment = @{}
        foreach ($environmentName in @($childEnvironment.Keys)) {
            $atomicEnvironment["$environmentName"] =
                [string]$childEnvironment[$environmentName]
            Assert-PrivateMarkerOperationTimeRemaining `
                -Stopwatch $operationStopwatch `
                -DeadlineMilliseconds $operationDeadlineMilliseconds
        }
        $atomicInput = if ($null -eq $StandardInputBytes) {
            [byte[]]@()
        } else {
            $StandardInputBytes
        }
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $operationStopwatch `
            -DeadlineMilliseconds $executionDeadlineMilliseconds
        $atomicResult = Invoke-PrivateMarkerAtomicWindowsProcess `
            -FilePath $FileName `
            -ArgumentList ([string[]]$Arguments) `
            -Environment $atomicEnvironment `
            -WorkingDirectory $WorkingDirectory `
            -StandardInputBytes $atomicInput `
            -OperationStopwatch $operationStopwatch `
            -OperationDeadlineMilliseconds $operationDeadlineMilliseconds `
            -ExecutionDeadlineMilliseconds $executionDeadlineMilliseconds `
            -DrainTimeoutMilliseconds $DrainTimeoutMilliseconds `
            -MaxStandardOutputBytes $MaxStdoutBytes `
            -MaxStandardErrorBytes $MaxStderrBytes `
            -ForceWindowsLaunchFailure $ForceWindowsLaunchFailure

        $atomicOutputLimitExceeded =
            -not [string]::IsNullOrEmpty($atomicResult.OutputLimitExceeded)
        $utf8 = [Text.UTF8Encoding]::new($false, $false)
        $atomicOutput = @(
            $utf8.GetString($atomicResult.StandardOutputBytes),
            $utf8.GetString($atomicResult.StandardErrorBytes)
        ) -join [Environment]::NewLine
        if ($atomicResult.TimedOut) {
            $atomicOutput += [Environment]::NewLine +
                "Process timed out after $TimeoutMilliseconds ms."
        }
        if ($atomicOutputLimitExceeded) {
            $atomicOutput += [Environment]::NewLine +
                'Process output exceeded the configured byte limit.'
        }
        return [pscustomobject]@{
            ExitCode = $atomicResult.ExitCode
            StdoutBytes = $atomicResult.StandardOutputBytes
            StderrBytes = $atomicResult.StandardErrorBytes
            Output = $atomicOutput.TrimEnd()
            TimedOut = $atomicResult.TimedOut
            OutputLimitExceeded = $atomicOutputLimitExceeded
            TreeStopped = $atomicResult.TreeStopped
            StreamsDrained = $atomicResult.StreamsDrained
        }
    }

    $process = $null
    $processStarted = $false
    $windowsJobHandle = [IntPtr]::Zero
    $posixProcessGroupId = 0
    $ownedTreeStopRequested = $false
    $stdinTask = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stdoutChunk = New-Object byte[] 8192
    $stderrChunk = New-Object byte[] 8192
    $stdoutBuffer = New-Object System.IO.MemoryStream
    $stderrBuffer = New-Object System.IO.MemoryStream
    $timedOut = $false
    $outputLimitExceeded = $false
    $treeStopped = $true
    $streamsDrained = $false
    $streamReadFailed = $false
    $exitCode = -1
    $stdoutBytes = [byte[]]@()
    $stderrBytes = [byte[]]@()
    try {
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $operationStopwatch `
            -DeadlineMilliseconds $executionDeadlineMilliseconds
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not (Start-PrivateMarkerProcessWithRawInput -Process $process)) {
            throw "Failed to start bounded child process: $FileName"
        }
        $processStarted = $true
        if ($usePosixProcessGroup) {
            if ($useNativePosixSessionGate) {
                $posixGateReady = $false
                while ((Get-PrivateMarkerRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $executionDeadlineMilliseconds) -gt 0) {
                    if ([IO.File]::Exists($posixGateReadyPath)) {
                        $posixGateReady = $true
                        break
                    }
                    if ($process.HasExited) {
                        break
                    }
                    $gateRemaining =
                        Get-PrivateMarkerRemainingMilliseconds `
                            -Stopwatch $operationStopwatch `
                            -DeadlineMilliseconds $executionDeadlineMilliseconds
                    if ($gateRemaining -gt 0) {
                        Start-Sleep -Milliseconds ([Math]::Min(
                            5,
                            $gateRemaining
                        ))
                    }
                }
                if (-not $posixGateReady) {
                    $cleanupWait =
                        Get-PrivateMarkerCappedRemainingMilliseconds `
                            -Stopwatch $operationStopwatch `
                            -DeadlineMilliseconds $operationDeadlineMilliseconds `
                            -MaximumMilliseconds $DrainTimeoutMilliseconds
                    [void](Stop-PrivateMarkerProcessTreeBounded `
                        -Process $process `
                        -WaitMilliseconds $cleanupWait)
                    throw 'Failed to establish the bounded POSIX session gate.'
                }
                # ready fileだけを信用せず、live wrapperが自分自身のgroup leader
                # であることを親側からも確認してからownershipを記録する。
                if ($process.HasExited -or
                    -not [AgenticCodingSecurityGate.PrivateMarkerPosixSignal]::
                        IsOwnedProcessGroup($process.Id, $process.Id)) {
                    $cleanupWait =
                        Get-PrivateMarkerCappedRemainingMilliseconds `
                            -Stopwatch $operationStopwatch `
                            -DeadlineMilliseconds $operationDeadlineMilliseconds `
                            -MaximumMilliseconds $DrainTimeoutMilliseconds
                    [void](Stop-PrivateMarkerProcessTreeBounded `
                        -Process $process `
                        -WaitMilliseconds $cleanupWait)
                    throw 'Failed to verify the bounded POSIX session owner.'
                }
                $posixProcessGroupId = $process.Id
                Assert-PrivateMarkerOperationTimeRemaining `
                    -Stopwatch $operationStopwatch `
                    -DeadlineMilliseconds $executionDeadlineMilliseconds
                try {
                    [IO.File]::WriteAllText(
                        $posixGateReleasePath,
                        'release',
                        [Text.UTF8Encoding]::new($false)
                    )
                }
                catch {
                    [void](Stop-PrivateMarkerPosixProcessGroupBounded `
                        -OwnerProcessId $process.Id `
                        -ProcessGroupId $posixProcessGroupId)
                    throw
                }
            }
        }
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $operationStopwatch `
            -DeadlineMilliseconds $executionDeadlineMilliseconds
        if ($null -ne $StandardInputBytes) {
            if ($StandardInputBytes.Length -eq 0) {
                $process.StandardInput.Close()
            } else {
                $stdinTask = $process.StandardInput.BaseStream.WriteAsync(
                    $StandardInputBytes,
                    0,
                    $StandardInputBytes.Length
                )
            }
        }
        $stdoutTask = $process.StandardOutput.BaseStream.ReadAsync(
            $stdoutChunk,
            0,
            $stdoutChunk.Length
        )
        $stderrTask = $process.StandardError.BaseStream.ReadAsync(
            $stderrChunk,
            0,
            $stderrChunk.Length
        )
        Assert-PrivateMarkerOperationTimeRemaining `
            -Stopwatch $operationStopwatch `
            -DeadlineMilliseconds $executionDeadlineMilliseconds

        # Poll both asynchronous byte reads and process state under one finite
        # deadline. This avoids ReadToEnd/CopyToAsync waits that can outlive the
        # child when a descendant inherits a redirected pipe.
        $stdoutClosed = $false
        $stderrClosed = $false
        $stdoutDiscarding = $false
        $stderrDiscarding = $false
        $stdinClosed = $null -eq $StandardInputBytes -or
            $StandardInputBytes.Length -eq 0
        $stdinWriteFailed = $false
        $exitObservedAt = -1L
        # Even if native tree termination itself fails, the helper must return
        # after one finite outer deadline instead of polling forever.
        $hardStopDeadlineMilliseconds = $operationDeadlineMilliseconds
        while ($operationStopwatch.ElapsedMilliseconds -lt
            $hardStopDeadlineMilliseconds) {
            if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                try {
                    [void]$stdinTask.GetAwaiter().GetResult()
                }
                catch {
                    $stdinWriteFailed = $true
                }
                try {
                    $process.StandardInput.Close()
                }
                catch {
                    $stdinWriteFailed = $true
                }
                $stdinClosed = $true
            }

            if (-not $stdoutClosed -and $stdoutTask.IsCompleted) {
                try {
                    $stdoutCount = $stdoutTask.GetAwaiter().GetResult()
                }
                catch {
                    $streamReadFailed = $true
                    $stdoutCount = 0
                }
                if ($stdoutCount -eq 0) {
                    $stdoutClosed = $true
                } elseif ($stdoutDiscarding -or
                    ($stdoutBuffer.Length + $stdoutCount) -gt
                    $MaxStdoutBytes) {
                    $outputLimitExceeded = $true
                    $stdoutDiscarding = $true
                    $stdoutTask = $process.StandardOutput.BaseStream.ReadAsync(
                        $stdoutChunk,
                        0,
                        $stdoutChunk.Length
                    )
                } else {
                    $stdoutBuffer.Write($stdoutChunk, 0, $stdoutCount)
                    $stdoutTask = $process.StandardOutput.BaseStream.ReadAsync(
                        $stdoutChunk,
                        0,
                        $stdoutChunk.Length
                    )
                }
            }

            if (-not $stderrClosed -and $stderrTask.IsCompleted) {
                try {
                    $stderrCount = $stderrTask.GetAwaiter().GetResult()
                }
                catch {
                    $streamReadFailed = $true
                    $stderrCount = 0
                }
                if ($stderrCount -eq 0) {
                    $stderrClosed = $true
                } elseif ($stderrDiscarding -or
                    ($stderrBuffer.Length + $stderrCount) -gt
                    $MaxStderrBytes) {
                    $outputLimitExceeded = $true
                    $stderrDiscarding = $true
                    $stderrTask = $process.StandardError.BaseStream.ReadAsync(
                        $stderrChunk,
                        0,
                        $stderrChunk.Length
                    )
                } else {
                    $stderrBuffer.Write($stderrChunk, 0, $stderrCount)
                    $stderrTask = $process.StandardError.BaseStream.ReadAsync(
                        $stderrChunk,
                        0,
                        $stderrChunk.Length
                    )
                }
            }

            # POSIX wrapperはtarget終了後もgroup leaderとして残る。固定長statusを
            # 受け取った時点でtarget codeを保存し、live anchorのままgroupを閉じる。
            if ($posixProcessGroupId -gt 0 -and
                $exitObservedAt -lt 0 -and
                [IO.File]::Exists($posixGateExitPath)) {
                try {
                    $statusItem = Get-Item `
                        -LiteralPath $posixGateExitPath `
                        -Force `
                        -ErrorAction Stop
                    if (($statusItem.Attributes -band
                            [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                        $statusItem.PSIsContainer -or
                        $statusItem.Length -lt 1 -or
                        $statusItem.Length -gt 16) {
                        throw 'Invalid bounded POSIX target status file.'
                    }
                    $statusText = [IO.File]::ReadAllText(
                        $posixGateExitPath,
                        [Text.Encoding]::ASCII
                    )
                    $targetExitCode = 0
                    if (-not [int]::TryParse(
                        $statusText,
                        [Globalization.NumberStyles]::AllowLeadingSign,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$targetExitCode
                    )) {
                        throw 'Invalid bounded POSIX target status value.'
                    }
                    $exitCode = $targetExitCode
                    $exitObservedAt =
                        $operationStopwatch.ElapsedMilliseconds
                }
                catch {
                    $treeStopped = $false
                    throw 'Invalid bounded POSIX target status.'
                }

                $ownedTreeStopRequested = $true
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $operationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                    -Process $process `
                    -WindowsJobHandle ([ref]$windowsJobHandle) `
                    -PosixProcessGroupId $posixProcessGroupId `
                    -WaitMilliseconds $cleanupWait
            }

            if ($outputLimitExceeded -and -not $ownedTreeStopRequested) {
                $ownedTreeStopRequested = $true
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $operationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                    -Process $process `
                    -WindowsJobHandle ([ref]$windowsJobHandle) `
                    -PosixProcessGroupId $posixProcessGroupId `
                    -WaitMilliseconds $cleanupWait
            }

            if (-not $process.HasExited -and
                $operationStopwatch.ElapsedMilliseconds -ge
                    $executionDeadlineMilliseconds) {
                $timedOut = $true
                if (-not $ownedTreeStopRequested) {
                    $ownedTreeStopRequested = $true
                    $cleanupWait =
                        Get-PrivateMarkerCappedRemainingMilliseconds `
                            -Stopwatch $operationStopwatch `
                            -DeadlineMilliseconds $operationDeadlineMilliseconds `
                            -MaximumMilliseconds $DrainTimeoutMilliseconds
                    $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                        -Process $process `
                        -WindowsJobHandle ([ref]$windowsJobHandle) `
                        -PosixProcessGroupId $posixProcessGroupId `
                        -WaitMilliseconds $cleanupWait
                }
            }

            if ($process.HasExited -and $exitObservedAt -lt 0) {
                $exitObservedAt = $operationStopwatch.ElapsedMilliseconds
                $exitCode = $process.ExitCode
                if ($posixProcessGroupId -gt 0 -and
                    -not $ownedTreeStopRequested) {
                    # containment後のanchor自発終了ではPGID ownershipを失う。
                    # 数値を再利用してnegative killせず、結果をfail closedにする。
                    $treeStopped = $false
                }
            }

            if ($process.HasExited -and $stdinClosed -and
                $stdoutClosed -and $stderrClosed) {
                $streamsDrained = -not $streamReadFailed -and
                    -not $stdinWriteFailed
                break
            }

            if ($exitObservedAt -ge 0 -and
                -not $ownedTreeStopRequested -and
                ($operationStopwatch.ElapsedMilliseconds - $exitObservedAt) -ge 250) {
                # Normal pipe EOF follows direct-child exit almost immediately.
                # A pipe still open after a short grace period is owned by a
                # descendant; close the job/process group before it can outlive
                # the bounded operation.
                $ownedTreeStopRequested = $true
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $operationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                    -Process $process `
                    -WindowsJobHandle ([ref]$windowsJobHandle) `
                    -PosixProcessGroupId $posixProcessGroupId `
                    -WaitMilliseconds $cleanupWait
            }

            if ($exitObservedAt -ge 0 -and
                ($operationStopwatch.ElapsedMilliseconds - $exitObservedAt) -ge
                $DrainTimeoutMilliseconds) {
                # A leaked descendant pipe or failed async read must make the
                # caller fail closed, but it must never hold this process open.
                $streamsDrained = $false
                break
            }

            $pollRemaining = Get-PrivateMarkerRemainingMilliseconds `
                -Stopwatch $operationStopwatch `
                -DeadlineMilliseconds $operationDeadlineMilliseconds
            if ($pollRemaining -gt 0) {
                Start-Sleep -Milliseconds ([Math]::Min(5, $pollRemaining))
            }
        }
        if ($operationStopwatch.ElapsedMilliseconds -ge
            $hardStopDeadlineMilliseconds) {
            $timedOut = $true
            $streamsDrained = $false
            if (-not $ownedTreeStopRequested) {
                $ownedTreeStopRequested = $true
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $operationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                    -Process $process `
                    -WindowsJobHandle ([ref]$windowsJobHandle) `
                    -PosixProcessGroupId $posixProcessGroupId `
                    -WaitMilliseconds $cleanupWait
            }
        }

        $stdoutBytes = $stdoutBuffer.ToArray()
        $stderrBytes = $stderrBuffer.ToArray()
    }
    finally {
        if ($null -ne $process) {
            if ($processStarted -and -not $process.HasExited) {
                $cleanupWait =
                    Get-PrivateMarkerCappedRemainingMilliseconds `
                        -Stopwatch $operationStopwatch `
                        -DeadlineMilliseconds $operationDeadlineMilliseconds `
                        -MaximumMilliseconds $DrainTimeoutMilliseconds
                $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                    -Process $process `
                    -WindowsJobHandle ([ref]$windowsJobHandle) `
                    -PosixProcessGroupId $posixProcessGroupId `
                    -WaitMilliseconds $cleanupWait
            } elseif ($windowsJobHandle -ne [IntPtr]::Zero) {
                $treeStopped =
                    [AgenticCodingSecurityGate.PrivateMarkerJob]::Close(
                        $windowsJobHandle
                    ) -and $treeStopped
                $windowsJobHandle = [IntPtr]::Zero
            } elseif ($posixProcessGroupId -gt 0 -and
                -not $ownedTreeStopRequested) {
                # ownerが既に終了していればnegative signalは禁止する。live anchor
                # の場合だけ通常のowned cleanup関数へ渡し、PID再利用を避ける。
                if ($process.HasExited) {
                    $treeStopped = $false
                } else {
                    $cleanupWait =
                        Get-PrivateMarkerCappedRemainingMilliseconds `
                            -Stopwatch $operationStopwatch `
                            -DeadlineMilliseconds $operationDeadlineMilliseconds `
                            -MaximumMilliseconds $DrainTimeoutMilliseconds
                    $treeStopped = Stop-PrivateMarkerOwnedProcessTreeBounded `
                        -Process $process `
                        -WindowsJobHandle ([ref]$windowsJobHandle) `
                        -PosixProcessGroupId $posixProcessGroupId `
                        -WaitMilliseconds $cleanupWait
                }
            }
            if ($startInfo.RedirectStandardInput) {
                try { $process.StandardInput.Dispose() } catch { }
            }
            $process.Dispose()
        } elseif ($windowsJobHandle -ne [IntPtr]::Zero) {
            [void][AgenticCodingSecurityGate.PrivateMarkerJob]::Close(
                $windowsJobHandle
            )
        }
        foreach ($gatePath in @(
            $posixGateReadyPath,
            $posixGateReleasePath,
            $posixGateExitPath,
            $(if ([string]::IsNullOrWhiteSpace($posixGateExitPath)) {
                $null
            } else {
                "$posixGateExitPath.tmp"
            })
        )) {
            if (-not [string]::IsNullOrWhiteSpace($gatePath)) {
                try { [IO.File]::Delete($gatePath) } catch { }
            }
        }
        $stdoutBuffer.Dispose()
        $stderrBuffer.Dispose()
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $false)
    $stdoutText = $utf8.GetString($stdoutBytes)
    $stderrText = $utf8.GetString($stderrBytes)
    $output = @($stdoutText, $stderrText) -join [Environment]::NewLine
    if ($timedOut) {
        $output += [Environment]::NewLine +
            "Process timed out after $TimeoutMilliseconds ms."
    }
    if (-not $treeStopped) {
        $output += [Environment]::NewLine +
            'Process tree did not stop within the bounded cleanup window.'
    }
    if (-not $streamsDrained) {
        $output += [Environment]::NewLine +
            'Process output streams did not close within the bounded drain window.'
    }
    if ($outputLimitExceeded) {
        $output += [Environment]::NewLine +
            'Process output exceeded the configured byte limit.'
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdoutBytes = $stdoutBytes
        StderrBytes = $stderrBytes
        Output = $output.TrimEnd()
        TimedOut = $timedOut
        OutputLimitExceeded = $outputLimitExceeded
        TreeStopped = $treeStopped
        StreamsDrained = $streamsDrained
    }
}
