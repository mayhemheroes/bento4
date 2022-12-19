#include <stdint.h>
#include <stdio.h>
#include <climits>

#include <fuzzer/FuzzedDataProvider.h>
#include "Ap4String.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FuzzedDataProvider provider(data, size);
    std::string s = provider.ConsumeRandomLengthString();
    char c = provider.ConsumeIntegral<char>();

    AP4_String ap4_string(s.c_str());
    ap4_string.Find(c);

    return 0;
}
