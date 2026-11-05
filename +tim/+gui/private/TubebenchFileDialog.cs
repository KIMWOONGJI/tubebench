// Helper of tim.gui.fileDialog (tubebench 1.6.2): the standard Windows file
// dialog with the program's window as its owner, so that Windows returns to
// the program when the dialog closes. Compiled at run time by the C# compiler
// of the .NET Framework (no C compiler needed).
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace TubebenchWin
{
    public static class Dialogs
    {
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

        class Owner : IWin32Window
        {
            public IntPtr Handle { get; set; }
        }

        // the foreground window when it belongs to a process of this name (0 otherwise)
        public static long ForegroundOf(string processName)
        {
            IntPtr h = GetForegroundWindow();
            if (h == IntPtr.Zero) return 0;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            try
            {
                Process p = Process.GetProcessById((int)pid);
                if (string.Equals(p.ProcessName, processName, StringComparison.OrdinalIgnoreCase)) return h.ToInt64();
            }
            catch (Exception) { }
            return 0;
        }

        // the chosen file ("" = cancelled); runs the dialog on its own STA thread
        public static string Show(bool save, long owner, string filter, string title, string folder, string name)
        {
            string result = "";
            Exception err = null;
            Thread t = new Thread(() =>
            {
                try
                {
                    FileDialog d;
                    if (save) d = new SaveFileDialog { OverwritePrompt = true };
                    else d = new OpenFileDialog { Multiselect = false, CheckFileExists = true };
                    using (d)
                    {
                        d.Filter = filter;
                        d.Title = title;
                        d.RestoreDirectory = true;
                        if (!string.IsNullOrEmpty(folder)) d.InitialDirectory = folder;
                        if (!string.IsNullOrEmpty(name)) d.FileName = name;
                        if (d.ShowDialog(new Owner { Handle = new IntPtr(owner) }) == DialogResult.OK) result = d.FileName;
                    }
                }
                catch (Exception e) { err = e; }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            t.Join();
            if (err != null) throw err;
            return result;
        }
    }
}
