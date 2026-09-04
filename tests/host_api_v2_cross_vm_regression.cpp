#include <iostream>
#include <string>

#include "VirtualMachine.hpp"

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: host_api_v2_cross_vm_regression <package-path>\n";
        return 2;
    }

    VirtualMachine first;
    VirtualMachine second;
    first.setPackageSearchPaths({argv[1]});
    second.setPackageSearchPaths({argv[1]});

    const std::string firstSource = R"(
const host = @import("host_api")
if (!host.stashForCrossVm([1i64, 2i64])) {
    error("could not create cross-VM fixture")
}
)";
    const std::string secondSource = R"(
const host = @import("host_api")
if (!host.crossVmRejected()) {
    error("foreign VM accepted a persistent value")
}
)";

    if (first.interpret(firstSource, false, false, false,
                        "/tmp/kelvra_host_api_first.kel") != Status::OK)
        return 1;
    if (second.interpret(secondSource, false, false, false,
                         "/tmp/kelvra_host_api_second.kel") != Status::OK)
        return 1;
    return 0;
}
