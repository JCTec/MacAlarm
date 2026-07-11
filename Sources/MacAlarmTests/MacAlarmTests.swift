import Foundation

#if canImport(Darwin)
    import Darwin
#endif

@main
struct MacAlarmTests {
    static func main() async {
        #if canImport(Darwin)
            if CommandLine.arguments.dropFirst().first == "--hold-exclusive-lock" {
                Foundation.exit(runExclusiveLockHelper(arguments: CommandLine.arguments))
            }
        #endif

        let runner = TestRunner()

        await runCoreTests(runner)
        await runCLIKitTests(runner)
        await runAgentRuntimeTests(runner)
        await runTimelineTests(runner)

        runner.finish()
    }

    #if canImport(Darwin)
        private static func runExclusiveLockHelper(arguments: [String]) -> Int32 {
            guard arguments.count == 4, let microseconds = useconds_t(arguments[3]) else {
                return 64
            }

            let fd = open(arguments[2], O_RDWR)
            guard fd >= 0 else {
                return 65
            }
            defer { close(fd) }

            guard flock(fd, LOCK_EX) == 0 else {
                return 66
            }
            defer { flock(fd, LOCK_UN) }

            FileHandle.standardOutput.write(Data("ready\n".utf8))
            usleep(microseconds)
            return 0
        }
    #endif
}
