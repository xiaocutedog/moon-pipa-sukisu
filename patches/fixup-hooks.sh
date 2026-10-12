#!/usr/bin/env bash
# fixup-hooks.sh
# 修正通用脚本 syscall_hook_patches.sh 在
#   SukiSU-Ultra builtin 分支 + CONFIG_KSU_SUSFS=n
# 组合下误判的两处 hook（否则链接期 undefined symbol）。
#
# 1) fs/read_write.c : 脚本误用 ksu_init_rc_hook（其实只是 ksud.c 里一句日志字符串），
#                      正确变量是 ksu_vfs_read_hook。
# 2) kernel/sys.c    : 脚本注入了 ksu_handle_setresuid，但该函数仅存在于
#                      hook/lsm_hook.c 的 #ifdef CONFIG_KSU_SUSFS 中；SUSFS 关闭时
#                      不存在。关闭 SUSFS 时 setuid 由 LSM 钩子 ksu_task_fix_setuid
#                      处理，无需该符号。
#
# 用法：在内核源码根目录执行  bash fixup-hooks.sh
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# 1) read: ksu_init_rc_hook -> ksu_vfs_read_hook
if [ -f fs/read_write.c ]; then
    sed -i 's/ksu_init_rc_hook/ksu_vfs_read_hook/g' fs/read_write.c
fi

# 2) sys.c: 删除对 ksu_handle_setresuid 的引用（保留空的 #ifdef/#endif，合法）
if [ -f kernel/sys.c ]; then
    sed -i '/ksu_handle_setresuid/d' kernel/sys.c
fi

fail=0
grep -q 'ksu_init_rc_hook' fs/read_write.c 2>/dev/null && { echo "[-] read_write.c still has ksu_init_rc_hook"; fail=1; }
grep -q 'ksu_handle_setresuid' kernel/sys.c 2>/dev/null && { echo "[-] sys.c still has ksu_handle_setresuid"; fail=1; }
[ "$fail" -ne 0 ] && { echo "[-] hook fixup failed"; exit 1; }

echo "[+] hook fixups applied (read->ksu_vfs_read_hook; dropped setresuid hook)"
grep -n 'ksu_vfs_read_hook' fs/read_write.c | head -3
