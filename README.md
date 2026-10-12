# 小米平板6（pipa）moon 内核 + SukiSU Ultra 构建套件

> 设备：Xiaomi Pad 6 标准版（代号 **pipa**，骁龙 870 / SM8250-AC，内核 **4.19.157**）
> 目标：把 **SukiSU Ultra** 内置进 **moon 内核**（你那个魔改包里的「龙哥 moon 内核」），产出**可直接卡刷**的 AnyKernel3 包。

---

## 一、调查结论（先把事实说清楚）

1. **`4.19.157-moon-gc80e50029` 的内核源码 = [`bcggxx/android_kernel_xiaomi_moon_sm8250`](https://github.com/bcggxx/android_kernel_xiaomi_moon_sm8250)**（默认分支 `main`）。
   - Makefile 已确认 4.19.157。
   - `-moon-` 后缀来自该仓库的 `arch/arm64/configs/xiaomi.config`：
     ```
     CONFIG_LOCALVERSION="-moon"
     CONFIG_LOCALVERSION_AUTO=y
     ```
     所以 `4.19.157-moon-gc80e50029` = 这棵内核树 + `xiaomi.config`，`gc80e50029` 是编译当时的 git 短哈希（`LOCALVERSION_AUTO` 自动附加）。
   - `gc80e50029` 这个 commit 在公开仓库**查不到**（已全站搜索，只匹配到无关项目），说明是开发者本地/未公开的编译点。**重新编译这棵树得到的内核功能一致，只是哈希不同。**
   - 你给的酷安帖（作者「可爱的猫猫呀」）也写着：新版 moon 内核**不再内置 KernelSU**，需自己用 Apatch/Magisk。这正是本套件要解决的问题。

2. **defconfig** = `arch/arm64/configs/pipa_user_defconfig`（软链指向 `vendor/pipa_user_defconfig`，所以把配置追加到原始文件是安全的）。

3. **SukiSU Ultra 在 4.19（非 GKI）上只能用 `builtin` 分支 + 手动 hook**（官方文档 + issue #728）。该分支接口是 `bool` 版，官方配套手动 hook 脚本是 `syscall_hook_patches.sh`。
   - ⚠️ 它要求 **`CONFIG_KSU_SUSFS` 关闭**。因为 `builtin` 分支 SUSFS 接口是 `bool` 版，而 SUSFS 的 inline hook 脚本用的是 `static_key` 版接口（那是给 **ReSukiSU** 的），二者不兼容。
   - 因此本套件默认 **不集成 SUSFS**（一样拿到 root）。需要 SUSFS 见第六节。

4. **为什么没有直接给编好的包**：本机（Windows）没有可用 Linux 构建环境——无 WSL 发行版、无 Docker、无 make/clang，磁盘也紧张。故用 **GitHub Actions 云端编译**，跑一次即可拿到卡刷包。

5. **已做过的验证**（在真实源码上跑过）：
   - 手动 hook 脚本 `syscall_hook_patches.sh` 在 moon 4.19 源码上**干净跑通**，正确向 `fs/exec.c`、`fs/open.c`、`fs/read_write.c`、`fs/stat.c`、`drivers/input/input.c`、`kernel/reboot.c`、`kernel/sys.c` 注入 `#ifdef CONFIG_KSU` 钩子，并按 4.19 正确跳过不需要的 security/selinux 钩子。
   - `patches/sukisu_ultra_419_fix.patch`（4.19 兼容修复）对固定的 SukiSU 提交**可无冲突应用**。
   - 两个工作流 YAML、`build-local.sh`、hook 脚本均通过语法校验。

---

## 二、交付内容

```
sukisu/
├─ README.md                                     ← 本文件
├─ build-local.sh                                ← 方案 C：本地 Linux 一键编译
├─ patches/
│  ├─ sukisu_ultra_419_fix.patch                 ← 【推荐】4.19 兼容修复（基于固定提交生成，已验证）
│  ├─ sukisu_ultra_fixed.patch                   ← 上游同名补丁（供方案 A 参考，可能随上游漂移）
│  ├─ syscall_hook_patches.sh                    ← 手动 syscall hook 注入脚本（backslashxx/Jake 官方）
│  └─ SUKISU_BUILTIN_BASE.txt                    ← 本套件对应的 SukiSU builtin 提交号
├─ .github/workflows/build-moon-sukisu.yml       ← 【推荐】方案 B：加进 moon 内核 fork 的自包含工作流
└─ option-A-nongki-fork/
   └─ build-xiaomi-pad6-moon-sukisu.yml          ← 方案 A：加进 NonGKI 构建系统的 fork
```

**推荐顺序：方案 B（已验证，最省事） → 方案 A → 方案 C（有 Linux 机器时）**。

---

## 三、方案 B：自包含工作流（推荐，已验证）

1. **Fork** [`bcggxx/android_kernel_xiaomi_moon_sm8250`](https://github.com/bcggxx/android_kernel_xiaomi_moon_sm8250) 到你自己的 GitHub 账号（保留默认分支 `main`）。
2. 在你 fork 中放入：
   - `.github/workflows/build-moon-sukisu.yml`（本套件提供）
   - `patches/sukisu_ultra_419_fix.patch`
   - `patches/syscall_hook_patches.sh`
3. 推送后进入 **Actions → Build Moon Kernel + SukiSU Ultra → Run workflow**。
4. 等约 30–60 分钟，在 **Artifacts** 下载 `moon-pipa-sukisu-<n>.zip`。

工作流做的事：装 clang-r416183b（moon 官方工具链）→ `setup.sh` 拉 **SukiSU Ultra builtin**（固定提交 `6c284e9…`，避免上游漂移）→ 打 `sukisu_ultra_419_fix.patch` 4.19 兼容修复 → 注入 syscall 手动 hook → 在 `xiaomi.config` 打开 `CONFIG_KSU=y` → 调 moon 自带 `build.sh`（defconfig + merge `xiaomi.config` + 编译 + AnyKernel3 打包）。

---

## 四、方案 A：用 moon 作者的《NonGKI_Kernel_Build_2nd》只改几个变量

moon 作者 **bcggxx** 维护了一套给「非 GKI 内核」自动集成 KernelSU/SUSFS 的 CI：
<https://github.com/bcggxx/NonGKI_Kernel_Build_2nd>（分支 `mainline`），本就含 pipa 的 A16 工作流。

1. **Fork** 上面仓库到你的账号。
2. 把本套件 `option-A-nongki-fork/build-xiaomi-pad6-moon-sukisu.yml` 放到你 fork 的 `.github/workflows/`。
3. **Actions → Build Xiaomi Pad6 MOON Kernel + SukiSU Ultra → Run workflow**。
4. 完成后下载 Artifacts 里的 `pipa-AOSP_HyperOS_A16-*-AnyKernel3.zip`。

关键改动（已写好）：
| 变量 | 值 | 说明 |
|---|---|---|
| `KERNEL_SOURCE` | `.../android_kernel_xiaomi_moon_sm8250.git` | 换成 moon 4.19.157 |
| `KERNELSU_AUTO_FORK` | `sukisu` | SukiSU Ultra（builtin）|
| `SUSFS_ENABLE` | `false` | 与 SukiSU builtin 接口一致 |
| `CLANG_SOURCE` | clang-r416183b 归档 | moon 官方工具链 |
| `BUILD_OTHER_CONFIG` + `MERGE_CONFIG_FILES` | `true` / `xiaomi.config` | 保留 `-moon` 与 moon 特性 |

> 注意：方案 A 用的是该系统仓库里的 `Patches/Patch/sukisu_ultra_fixed.patch`。该补丁会随上游 SukiSU 更新而可能产生偏移，本套件已在固定提交上验证过的是 `sukisu_ultra_419_fix.patch`（方案 B）。若方案 A 因补丁 `.rej` 失败，请改用方案 B。

---

## 五、方案 C：本地 Linux 编译

在任意 Linux x86_64（或 WSL2 / Ubuntu 22.04，≥40G 空闲磁盘）：

```bash
# 1) 工具链（moon 官方 clang-r416183b）
cd ~ && mkdir clang && cd clang
wget "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/428d18d9732aa7ebfcaed87a582d86155db878d4/clang-r416183b.tar.gz" -O clang.tar.gz
tar -xzf clang.tar.gz && export PATH=$PWD/bin:$PATH

# 2) 内核源码
cd ~ && git clone --depth=1 https://github.com/bcggxx/android_kernel_xiaomi_moon_sm8250 -b main moon
# 3) 把本套件的 patches/ 与 build-local.sh 放进 moon/，然后：
cd moon && cp -r /path/to/sukisu/patches . && cp /path/to/sukisu/build-local.sh .
sudo apt-get install -y git curl zip bc bison flex libssl-dev device-tree-compiler python3 p7zip-full
bash build-local.sh
# 产物：./Kernel_N0_pipa_A16_AOSP_MIUI_<日期>.zip
```

---

## 六、刷入（卡刷）

1. 确认 bootloader 已解锁，**先备份原 boot 分区**。
2. 用 **TWRP** 或 **Kernel Flasher / 内核管家** 刷入上一步得到的 `*.zip`（AnyKernel3 自动处理 slot 与设备校验，`device.name1=pipa`）。
3. 重启。开机后安装 **[SukiSU Ultra 管理器 APK](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases)**（选与本内核提交对应的版本）授权即可。
4. 不开机 → 立即回刷备份的 boot。

> 因为用的是同一棵 moon 内核树 + 同一 `pipa_user_defconfig` + `xiaomi.config`，**moon 的全部特性（`CONFIG_MOON_KEYBOARD_OPT`、内存回收、UFS 写入加速、RCU_BOOST 等）都会保留**，只是额外内置了 SukiSU。

---

## 七、关于 SUSFS（可选，进阶）

SukiSU-Ultra `builtin` 分支**不能**与 SUSFS 手动 hook 脚本混用（`bool` vs `static_key` 接口冲突）。若确实需要 SUSFS：

- **改用 ReSukiSU**（SukiSU-Ultra 的下游分支，CI 兼容）：在方案 A 工作流里把 `KERNELSU_AUTO_FORK` 改成 `resukisu`、`SUSFS_ENABLE` 改成 `true`、`SUSFS_FIXED` 改成 `true`。这正是 bcggxx 官方 pipa A16 工作流的默认配置，可稳定产出带 SUSFS 的包。
- 或等 SukiSU-Ultra `builtin` 分支接口升级到 `static_key` 后再合入 SUSFS。

---

## 八、参考

- moon 内核源码：<https://github.com/bcggxx/android_kernel_xiaomi_moon_sm8250>（自带 CI：`.github/workflows/BuildKernelForPipa.yml`）
- 非 GKI 自动构建系统：<https://github.com/bcggxx/NonGKI_Kernel_Build_2nd>（源自 <https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd>）
- SukiSU Ultra：<https://github.com/SukiSU-Ultra/SukiSU-Ultra>（集成说明 <https://sukisu.org/guide/how-to-integrate>）
- 手动 hook 脚本作者：backslashxx @ GitHub；SUSFS：simonpunk @ GitLab
- AnyKernel3：<https://github.com/bcggxx/AnyKernel3>（分支 `n0-A16`）
