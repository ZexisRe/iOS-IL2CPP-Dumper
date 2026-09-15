#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Decrypt-copy a Mach-O from a live process (FairPlay decrypted in memory). Returns output path or nil.
NSString *_Nullable FDMemoryDumpImage(pid_t pid, NSString *sourcePath, NSString *destPath, NSError **_Nullable error);

/// First pid whose main executable path contains `executableName`, or 0.
pid_t FDFindPidByExecutableName(NSString *executableName);

NS_ASSUME_NONNULL_END
