#import <Foundation/Foundation.h>
#import <Security/Security.h>
typedef struct __SecCodeSigner *SecCodeSignerRef;
extern const CFStringRef kSecCodeSignerIdentity;
extern const CFStringRef kSecCodeSignerIdentifier;
extern OSStatus SecCodeSignerCreate(CFDictionaryRef, SecCSFlags, SecCodeSignerRef *);
extern OSStatus SecCodeSignerAddSignature(SecCodeSignerRef, SecStaticCodeRef, SecCSFlags);
static void check(OSStatus status, const char *step) {
    if (status != errSecSuccess) {
        CFStringRef message = SecCopyErrorMessageString(status, NULL);
        fprintf(stderr, "%s: %d %s\n", step, (int)status, [(__bridge NSString *)message UTF8String]);
        if (message) CFRelease(message);
        exit(1);
    }
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    NSData *data = [NSData dataWithContentsOfFile:@(argv[2])];
    NSString *password = NSProcessInfo.processInfo.environment[@"MACDUO_P12_PASSWORD"];
    NSDictionary *options = @{(__bridge id)kSecImportExportPassphrase: password, (__bridge id)kSecImportToMemoryOnly: @YES};
    CFArrayRef imported = NULL;
    check(SecPKCS12Import((__bridge CFDataRef)data, (__bridge CFDictionaryRef)options, &imported), "Import local identity in memory");
    SecIdentityRef identity = (__bridge SecIdentityRef)((__bridge NSArray *)imported)[0][(__bridge id)kSecImportItemIdentity];
    NSDictionary *parameters = @{(__bridge id)kSecCodeSignerIdentity: (__bridge id)identity,
                                 (__bridge id)kSecCodeSignerIdentifier: @"local.macduo.app"};
    SecCodeSignerRef signer = NULL;
    check(SecCodeSignerCreate((__bridge CFDictionaryRef)parameters, kSecCSDefaultFlags, &signer), "Create signer");
    SecStaticCodeRef code = NULL;
    check(SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[1])], kSecCSDefaultFlags, &code), "Open app");
    check(SecCodeSignerAddSignature(signer, code, kSecCSDefaultFlags), "Sign app");
    CFRelease(code); CFRelease(signer); CFRelease(imported);
    return 0;
} }
