# LidWifiHibernate

Windows 11 合盖休眠规避工具。合盖时先禁用 MediaTek MT7922（RZ616）无线网卡，再请求休眠，恢复后重新启用网卡。

> **请按自己的电脑适配网卡。** 当前预编译 EXE 默认只匹配 MediaTek MT7922（RZ616，PCI 硬件 ID 为 VEN_14C3 / DEV_0616）。使用其他网卡时，请先修改源码中的设备匹配条件，再重新编译和安装。

## 适配其他无线网卡

1. 在 PowerShell 运行：

```powershell
Get-PnpDevice -PresentOnly -Class Net | Format-Table FriendlyName, InstanceId -AutoSize
```

2. 找到实体无线网卡。编辑 WifiPower.ps1，将匹配条件 PCI\VEN_14C3&DEV_0616&* 改成自己的网卡 ID。要针对一台电脑精确匹配，可用 InstanceId -eq '你的完整设备实例 ID'。确保只匹配一张实体 Wi-Fi 网卡。
3. 运行 build.bat 将脚本嵌入新的 EXE，再以管理员身份运行安装脚本。仅编辑外部 PS1 不会改变已编译的 EXE。

## 背景与实测

一台 HP EliteBook 845 G10 在 Windows 11 26300.9974 上多次于休眠恢复时蓝屏重启。三份转储均记录了 0x139 / 0x3，异常都落在 tcpip.sys+0x47522。更换代理客户端和改用 2.4 GHz 后仍有复发。在这台机器上，休眠前禁用网卡、恢复后重新启用，已通过实际合盖测试。这个办法是针对该环境的规避措施，现有转储不足以确定根因。

## 工作原理

1. 登录计划任务以管理员权限启动后台程序。程序订阅 Windows 的合盖电源通知。
2. 安装脚本把插电、用电池时的合盖动作设为“不采取任何操作”，避免系统抢先休眠。
3. 合盖时先注册一次性开机恢复任务，再禁用 MT7922。只有设备问题码为 22（已禁用）才请求休眠。
4. 正常唤醒后重新启用网卡。如果唤醒时蓝屏重启，一次性启动任务会尝试恢复网卡。日志写到实际运行的 EXE 同目录。

[微软的电源通知说明](https://learn.microsoft.com/en-us/windows/win32/power/registering-for-power-events)

## 安装

在 Windows x64 上，将 LidWifiHibernate.exe 和 Install-LidWifiHibernate.ps1 放在同一目录。在管理员 PowerShell 中切到该目录，运行：

```powershell
.\Install-LidWifiHibernate.ps1
```

默认日志：C:\Program Files\MT7922-Lid-Auto\power.log。

首次合盖请保存工作，在桌面上确认已经进入休眠并且唤醒后 Wi-Fi 恢复。监听器未运行时，合盖会保持开机。程序只处理合盖通知。开始菜单关机、系统空闲休眠和登录前的合盖不经过这套流程。项目版本自动匹配唯一一张 MT7922 PCI 网卡，未在其他机型验证。

## 恢复原来的合盖行为

以管理员身份运行：

```powershell
.\Install-LidWifiHibernate.ps1 -Undo
```

这会移除登录任务，并将当前电源计划的合盖动作设回“休眠”。如果 Wi-Fi 仍然禁用，可在设备管理器重新启用 MT7922，或以管理员身份运行 .\WifiPower.ps1 -Mode Restore。

## 从源码构建

LidWindow.cs 是后台监听器。WifiPower.ps1 在编译时嵌入 EXE，负责网卡和电源操作。双击 build.bat，使用 Windows 自带的 .NET Framework x64 C# 编译器生成 LidWifiHibernate.exe。编译后重跑安装脚本更新已安装版本。


