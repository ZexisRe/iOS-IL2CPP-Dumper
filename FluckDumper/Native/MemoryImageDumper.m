// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

#import "MemoryImageDumper.h"

#import <mach/mach.h>
#import <mach/vm_region.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <sys/sysctl.h>
#import <string.h>
#import <stdlib.h>

static BOOL fd_read_file(NSData *data, size_t offset, void *dst, size_t len) {
    if (offset + len > data.length) return NO;
    [data getBytes:dst range:NSMakeRange(offset, len)];
    return YES;
}

static uint32_t fd_cryptid_in_mach64(NSData *data, size_t offset) {
    if (data.length < offset + sizeof(struct mach_header_64)) return 0;
    struct mach_header_64 mh;
    if (!fd_read_file(data, offset, &mh, sizeof(mh))) return 0;
    size_t cmd_off = offset + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh.ncmds; i++) {
        struct load_command lc;
        if (!fd_read_file(data, cmd_off, &lc, sizeof(lc))) break;
        if (lc.cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command_64 enc;
            if (!fd_read_file(data, cmd_off, &enc, sizeof(enc))) return 0;
            return enc.cryptid;
        }
        cmd_off += lc.cmdsize;
    }
    return 0;
}

static BOOL fd_zero_cryptid_in_mach64(NSMutableData *data, size_t offset) {
    if (data.length < offset + sizeof(struct mach_header_64)) return NO;
    struct mach_header_64 mh;
    if (!fd_read_file(data, offset, &mh, sizeof(mh))) return NO;
    size_t cmd_off = offset + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh.ncmds; i++) {
        struct load_command lc;
        if (!fd_read_file(data, cmd_off, &lc, sizeof(lc))) break;
        if (lc.cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command_64 enc;
            if (!fd_read_file(data, cmd_off, &enc, sizeof(enc))) return NO;
            enc.cryptid = 0;
            [data replaceBytesInRange:NSMakeRange(cmd_off, sizeof(enc)) withBytes:&enc];
            return YES;
        }
        cmd_off += lc.cmdsize;
    }
    return NO;
}

pid_t FDFindPidByExecutableName(NSString *executableName) {
    if (executableName.length == 0) return 0;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return 0;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return 0;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
        free(procs);
        return 0;
    }
    int count = (int)(size / sizeof(struct kinfo_proc));
    pid_t found = 0;
    const char *want = executableName.UTF8String;
    size_t wantLen = strlen(want);
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1) continue;
        const char *comm = procs[i].kp_proc.p_comm;
        if (strncmp(comm, want, MAXCOMLEN) == 0) {
            found = pid;
            break;
        }
        if (wantLen <= MAXCOMLEN && strncmp(comm, want, wantLen) == 0) {
            found = pid;
            break;
        }
    }
    free(procs);
    return found;
}

static kern_return_t fd_read_remote(task_t task, vm_address_t addr, void *buf, vm_size_t size) {
    vm_size_t out = 0;
    return vm_read_overwrite(task, addr, size, (vm_address_t)buf, &out);
}

static vm_address_t fd_find_remote_image(task_t task, NSData *fileData, size_t machOffset) {
    struct mach_header_64 mh;
    if (!fd_read_file(fileData, machOffset, &mh, sizeof(mh))) return 0;
    if (mh.magic != MH_MAGIC_64) return 0;

    vm_address_t addr = 0;
    vm_size_t size = 0;
    natural_t depth = 0;
    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_recurse_64(task, &addr, &size, &depth,
                                                (vm_region_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;
        if (info.is_submap) {
            depth++;
            continue;
        }
        if (size >= sizeof(struct mach_header_64)) {
            struct mach_header_64 remote;
            if (fd_read_remote(task, addr, &remote, sizeof(remote)) == KERN_SUCCESS) {
                if (remote.magic == MH_MAGIC_64 && remote.filetype == mh.filetype &&
                    remote.cputype == mh.cputype && remote.ncmds == mh.ncmds) {
                    return addr;
                }
            }
        }
        addr += size;
    }
    return 0;
}

NSString *FDMemoryDumpImage(pid_t pid, NSString *sourcePath, NSString *destPath, NSError **error) {
    NSData *fileData = [NSData dataWithContentsOfFile:sourcePath];
    if (!fileData) {
        if (error) *error = [NSError errorWithDomain:@"com.zexis.iosil2cppdumper" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot read source Mach-O"}];
        return nil;
    }

    size_t machOffset = 0;
    uint32_t magic = 0;
    [fileData getBytes:&magic length:4];
    if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        struct fat_header fh;
        [fileData getBytes:&fh length:sizeof(fh)];
        struct fat_arch arch;
        [fileData getBytes:&arch range:NSMakeRange(sizeof(fh), sizeof(arch))];
        machOffset = NXSwapLong(arch.offset);
    }

    if (fd_cryptid_in_mach64(fileData, machOffset) == 0) {
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destPath error:error];
        return destPath;
    }

    task_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS || task == MACH_PORT_NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zexis.iosil2cppdumper" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"task_for_pid failed — launch the game first, or check entitlements."}];
        }
        return nil;
    }

    vm_address_t base = fd_find_remote_image(task, fileData, machOffset);
    if (base == 0) {
        mach_port_deallocate(mach_task_self(), task);
        if (error) {
            *error = [NSError errorWithDomain:@"com.zexis.iosil2cppdumper" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not find this Mach-O in process memory — keep the app open in foreground."}];
        }
        return nil;
    }

    NSMutableData *out = [fileData mutableCopy];
    struct mach_header_64 mh;
    fd_read_file(fileData, machOffset, &mh, sizeof(mh));
    size_t cmd_off = machOffset + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh.ncmds; i++) {
        struct load_command lc;
        fd_read_file(fileData, cmd_off, &lc, sizeof(lc));
        if (lc.cmd == LC_SEGMENT_64) {
            struct segment_command_64 seg;
            fd_read_file(fileData, cmd_off, &seg, sizeof(seg));
            if (seg.vmsize > 0 && seg.filesize > 0) {
                void *segBuf = malloc((size_t)seg.filesize);
                if (segBuf) {
                    vm_address_t remote = (vm_address_t)(base + seg.vmaddr);
                    if (fd_read_remote(task, remote, segBuf, seg.filesize) == KERN_SUCCESS) {
                        if (seg.fileoff + seg.filesize <= out.length) {
                            [out replaceBytesInRange:NSMakeRange(seg.fileoff, (NSUInteger)seg.filesize) withBytes:segBuf];
                        }
                    }
                    free(segBuf);
                }
            }
        }
        cmd_off += lc.cmdsize;
    }

    fd_zero_cryptid_in_mach64(out, machOffset);
    [out writeToFile:destPath atomically:YES];
    mach_port_deallocate(mach_task_self(), task);
    return destPath;
}
