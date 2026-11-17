using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

sealed class LidWindow : Form
{
    [DllImport("user32.dll", SetLastError=true)]
    static extern IntPtr RegisterPowerSettingNotification(IntPtr window, ref Guid setting, int flags);
    [DllImport("user32.dll")]
    static extern bool UnregisterPowerSettingNotification(IntPtr handle);

    Guid lid = new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
    IntPtr registration;
    bool sawOpen, busy;

    [STAThread]
    static void Main()
    {
        using(var identity=WindowsIdentity.GetCurrent())
        if(!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
        {
            try { Process.Start(new ProcessStartInfo(Application.ExecutablePath) { Verb="runas", UseShellExecute=true }); }
            catch(System.ComponentModel.Win32Exception) { }
            return;
        }
        bool first;
        using(var mutex=new System.Threading.Mutex(true,"Local\\MT7922LidTool",out first))
        {
            if(!first) return;
            
            using (var listener = new LidWindow()) { if (listener.registration != IntPtr.Zero) Application.Run(); else Environment.ExitCode = 1; }
        }
    }

    LidWindow()
    {
        registration = RegisterPowerSettingNotification(Handle, ref lid, 0);
        Log("Listener registered: " + (registration != IntPtr.Zero));
    }

    protected override void Dispose(bool disposing)
    {
        if(registration != IntPtr.Zero)
        {
            UnregisterPowerSettingNotification(registration);
            registration = IntPtr.Zero;
        }
        base.Dispose(disposing);
    }

    static void Log(string message)
    {
        try {
            string dir=Application.StartupPath;
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir,"power.log"),DateTimeOffset.Now.ToString("o")+" "+message+Environment.NewLine);
        } catch (IOException) {} catch (UnauthorizedAccessException) {}
    }

    protected override void WndProc(ref Message m)
    {
        if(m.Msg==0x218 && m.WParam.ToInt64()==0x8013 && m.LParam!=IntPtr.Zero &&
           (Guid)Marshal.PtrToStructure(m.LParam,typeof(Guid))==lid && Marshal.ReadInt32(m.LParam,16)>=4)
        {
            int state=Marshal.ReadInt32(m.LParam,20); Log("Lid notification: "+state+"; busy="+busy);
            if(state==1) sawOpen=true;
            if(state==0 && sawOpen)
            {
                sawOpen=false;
                if(!busy) BeginInvoke(new Action(() => { if(!sawOpen) Run("Hibernate"); }));
            }
        }
        base.WndProc(ref m);
    }

    async void Run(string mode)
    {
        if(busy) return;
        busy=true; Log("Launching "+mode);
        try
        {
            await Task.Run(() => {
                string script;
                using(var reader=new StreamReader(typeof(LidWindow).Assembly.GetManifestResourceStream("power.ps1")))
                    script=reader.ReadToEnd();
                string code="& {\n"+script+"\n} -Mode "+mode;
                string encoded=Convert.ToBase64String(Encoding.Unicode.GetBytes(code));
                var info=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),"-NoProfile -NonInteractive -EncodedCommand "+encoded) {
                    UseShellExecute=false, CreateNoWindow=true, RedirectStandardError=true
                };
                info.EnvironmentVariables["MT7922_LOG_DIR"]=Application.StartupPath;
                using(var process=Process.Start(info)){
                    string error=process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    if(process.ExitCode!=0) throw new InvalidOperationException(error.Trim());
                }
            });
        }
        catch(Exception ex)
        {
            Log("Operation failed: "+ex.Message);
        }
        finally { busy=false; }
    }
}




