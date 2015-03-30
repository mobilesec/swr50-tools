#!/system/bin/sh
#
# SuperSU installer ZIP 
# Copyright (c) 2012-2014 - Chainfire
# Copyright (c) 2014-2015 - Michael Roland, u'smile
# 
# To install SuperSU properly, aside from cleaning old versions and
# other superuser-type apps from the system, the following files need to
# be installed:
#
# API   source                        target                              chmod   chcon                       required
#
# 17+   common/install-recovery.sh    /system/etc/install-recovery.sh     0755    *1                          required
# 17+                                 /system/bin/install-recovery.sh     (symlink to /system/etc/...)        required
# *1: same as /system/bin/toolbox: u:object_r:system_file:s0 if API < 20, u:object_r:toolbox_exec:s0 if API >= 20
#
# 7+    /sbin/su                      /system/xbin/su                     *2      u:object_r:system_file:s0   required
# 17+                                 /system/xbin/daemonsu               0755    u:object_r:system_file:s0   required
# 17+                                 /system/xbin/sugote                 0755    u:object_r:zygote_exec:s0   required
# *2: 06755 if API < 18, 0755 if API >= 18
#
# 19+   /sbin/supolicy                /system/xbin/supolicy               0755    u:object_r:system_file:s0   required
# 19+   /sbin/libsupol.so             /system/lib(64)/libsupol.so         0644    u:object_r:system_file:s0   required
#
# 17+   /system/bin/sh or mksh *3     /system/xbin/sugote-mksh            0755    u:object_r:system_file:s0   required
# *3: which one (or both) are available depends on API
#
# 21+   /system/bin/app_process32     /system/bin/app_process32_original  0755    u:object_r:zygote_exec:s0   required
# 21+   /system/bin/app_process32     /system/bin/app_process_init        0755    u:object_r:system_file:s0   required
# 21+                                 /system/bin/app_process             (symlink to /system/xbin/daemonsu)  required
# 21+                                 /system/bin/app_process32           (symlink to /system/xbin/daemonsu)  required
#
# 17+   common/99SuperSUDaemon *5     /system/etc/init.d/99SuperSUDaemon  0755    u:object_r:system_file:s0   optional
# *5: only place this file if /system/etc/init.d is present
#
# 17+   'echo 1 >' or 'touch' *6      /system/etc/.installed_su_daemon    0644    u:object_r:system_file:s0   optional
# *6: the file just needs to exist or some recoveries will nag you. Even with it there, it may still happen.
#
# It may seem some files are installed multiple times needlessly, but
# it only seems that way. Installing files differently or symlinking
# instead of copying (unless specified) will lead to issues eventually.
#
# The following su binary versions are included in the full package: arm-v7a.
#
# Note that if SELinux is set to enforcing, the daemonsu binary expects 
# to be run at startup (usually from install-recovery.sh, 99SuperSUDaemon,
# or app_process) from u:r:init:s0 or u:r:kernel:s0 contexts. Depending
# on the current policies, it can also deal with u:r:init_shell:s0 and
# u:r:toolbox:s0 contexts. Any other context will lead to issues eventually.
#
# After installation, run '/system/xbin/su --install', which may need to
# perform some additional installation steps. Ideally, at one point,
# a lot of this script will be moved there.
#
# The script performs serveral actions in various ways, sometimes
# multiple times, due to different recoveries and firmwares behaving
# differently, and it thus being required for the correct result.

/system/bin/sleep 3

start_log() {
  /system/bin/rm -f /system/etc/superuser.log
  /system/bin/touch /system/etc/superuser.log
  /system/bin/chmod 644 /system/etc/superuser.log
}

print_log() {
  echo -n -e "$1\n" >> /system/etc/superuser.log
}

ch_con() {
  /system/bin/toolbox chcon -h u:object_r:system_file:s0 $1
  /system/bin/toolbox chcon u:object_r:system_file:s0 $1
}

ch_con_ext() {
  /system/bin/toolbox chcon $2 $1
}

ln_con() {
  /system/bin/toolbox ln -s $1 $2
  ch_con $2
}

set_perm() {
  /system/bin/chown $1.$2 $4
  /system/bin/chown $1:$2 $4
  /system/bin/chmod $3 $4
  ch_con $4
  ch_con_ext $4 $5
}

cp_perm() {
  /system/bin/rm $5
  /system/bin/cat $4 > $5
  set_perm $1 $2 $3 $5 $6
}

start_log

print_log "Mounting /system and /data"
/system/bin/mount /system
/system/bin/mount /data

print_log "Re-mounting /system for read/write"
/system/bin/mount -o remount,rw /system

print_log "Discovering system configuration"
BUILDID=$(cat /system/build.prop | grep "ro.build.id=" | dd bs=1 skip=12)
API=$(cat /system/build.prop | grep "ro.build.version.sdk=" | dd bs=1 skip=21 count=2)
SUMOD=06755
SUGOTE=false
SUPOLICY=false
INSTALL_RECOVERY_CONTEXT=u:object_r:system_file:s0
MKSH=/system/bin/mksh
APPPROCESS=false
if [ "$API" -eq "$API" ]; then
  if [ "$API" -ge "17" ]; then
    SUGOTE=true
  fi
  if [ "$API" -ge "18" ]; then
    SUMOD=0755
  fi
  if [ "$API" -ge "19" ]; then
    SUPOLICY=true
    if [ "$(/system/bin/ls -lZ /system/bin/toolbox | /system/bin/grep toolbox_exec > /dev/null; echo $?)" -eq "0" ]; then 
      INSTALL_RECOVERY_CONTEXT=u:object_r:toolbox_exec:s0
    fi
  fi
  if [ "$API" -ge "21" ]; then
    APPPROCESS=true
  fi
fi
if [ ! -f $MKSH ]; then
  MKSH=/system/bin/sh
fi

print_log "Configuration:"
print_log "    BUILDID=$BUILDID"
print_log "    API=$API"
print_log "    SHELL=$MKSH"
print_log "    SUMOD=$SUMOD"
print_log "    SUGOTE=$SUGOTE"
print_log "    SUPOLICY=$SUPOLICY"
print_log "    INSTALL_RECOVERY_CONTEXT=$INSTALL_RECOVERY_CONTEXT"
print_log "    APPPROCESS=$APPPROCESS"

print_log "Creating backup of install-recovery.sh"
if [ -f "/system/bin/install-recovery.sh" ]; then
  if [ ! -f "/system/bin/install-recovery_original_$BUILDID.sh" ]; then
    /system/bin/mv /system/bin/install-recovery.sh /system/bin/install-recovery_original_$BUILDID.sh
    ch_con /system/bin/install-recovery_original_$BUILDID.sh
    chmod 755 /system/bin/install-recovery_original_$BUILDID.sh
	echo -n -e "#/system/bin/sh\n/system/bin/install-recovery_original_$BUILDID.sh\n" > /system/bin/install-recovery_original.sh
    ch_con /system/bin/install-recovery_original.sh
    chmod 755 /system/bin/install-recovery_original.sh
  fi
fi
if [ -f "/system/etc/install-recovery.sh" ]; then
  if [ ! -f "/system/etc/install-recovery_original_$BUILDID.sh" ]; then
    /system/bin/mv /system/etc/install-recovery.sh /system/etc/install-recovery_original_$BUILDID.sh
    ch_con /system/etc/install-recovery_original_$BUILDID.sh
    chmod 755 /system/etc/install-recovery_original_$BUILDID.sh
	echo -n -e "#/system/bin/sh\n/system/etc/install-recovery_original_$BUILDID.sh\n" > /system/etc/install-recovery_original.sh
    ch_con /system/etc/install-recovery_original.sh
    chmod 755 /system/etc/install-recovery_original.sh
  fi
fi

print_log "Removing old files"
/system/bin/rm -f /system/bin/su
/system/bin/rm -f /system/xbin/su
/system/bin/rm -f /system/xbin/daemonsu
/system/bin/rm -f /system/xbin/sugote
/system/bin/rm -f /system/xbin/sugote-mksh
/system/bin/rm -f /system/xbin/supolicy
/system/bin/rm -f /system/lib/libsupol.so
/system/bin/rm -f /system/bin/.ext/.su
/system/bin/rm -f /system/bin/install-recovery.sh
/system/bin/rm -f /system/etc/install-recovery.sh
/system/bin/rm -f /system/etc/init.d/99SuperSUDaemon
/system/bin/rm -f /system/etc/.installed_su_daemon

print_log "Installing su/daemonsu"
cp_perm 0 0 $SUMOD /sbin/su /system/xbin/su
cp_perm 0 0 0755 /sbin/su /system/xbin/daemonsu
if ($SUGOTE); then
  cp_perm 0 0 0755 /sbin/su /system/xbin/sugote u:object_r:zygote_exec:s0
  cp_perm 0 0 0755 $MKSH /system/xbin/sugote-mksh
fi
if ($SUPOLICY); then
  cp_perm 0 0 0755 /sbin/supolicy /system/xbin/supolicy
  cp_perm 0 0 0644 /sbin/libsupol.so /system/lib/libsupol.so
fi
cp_perm 0 0 0755 /sbin/install-recovery.sh /system/etc/install-recovery.sh
ln_con /system/etc/install-recovery.sh /system/bin/install-recovery.sh
if ($APPPROCESS); then
  /system/bin/rm /system/bin/app_process
  ln_con /system/xbin/daemonsu /system/bin/app_process
  if [ ! -f "/system/bin/app_process32_original" ]; then
    /system/bin/mv /system/bin/app_process32 /system/bin/app_process32_original
    /system/bin/mv /system/bin/app_process32 /system/bin/app_process32_original_$BUILDID
  else
    rm /system/bin/app_process32
  fi
  ln_con /system/xbin/daemonsu /system/bin/app_process32
  if [ ! -f "/system/bin/app_process_init" ]; then
    cp_perm 0 2000 0755 /system/bin/app_process32_original /system/bin/app_process_init
  fi
fi
#cp_perm 0 0 0744 /sbin/99SuperSUDaemon /system/etc/init.d/99SuperSUDaemon
#echo 1 > /system/etc/.installed_su_daemon
#set_perm 0 0 0644 /system/etc/.installed_su_daemon

print_log "Committing changes"
/system/bin/sync
/system/bin/sleep 3

print_log "Calling su self-installation"
/system/xbin/su --install

print_log "Committing changes"
/system/bin/sync
/system/bin/sleep 3

/system/bin/reboot
