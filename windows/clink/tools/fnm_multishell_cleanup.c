/* After the given PID exits, remove that session's fnm_multishells link. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
	int argc = 0;
	DWORD pid;
	HANDLE proc;
	DWORD attr;
	LPWSTR *argv;

	(void)inst;
	(void)prev;
	(void)cmd;
	(void)show;

	argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	if (!argv || argc < 3)
		return 1;

	pid = (DWORD)wcstoul(argv[1], NULL, 10);
	if (!pid || !wcsstr(argv[2], L"fnm_multishells")) {
		LocalFree(argv);
		return 1;
	}

	proc = OpenProcess(SYNCHRONIZE, FALSE, pid);
	if (!proc) {
		LocalFree(argv);
		return 1;
	}
	WaitForSingleObject(proc, INFINITE);
	CloseHandle(proc);

	attr = GetFileAttributesW(argv[2]);
	if (attr != INVALID_FILE_ATTRIBUTES) {
		if (attr & FILE_ATTRIBUTE_DIRECTORY)
			RemoveDirectoryW(argv[2]);
		else
			DeleteFileW(argv[2]);
	}

	LocalFree(argv);
	return 0;
}
