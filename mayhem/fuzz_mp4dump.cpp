// In-process libFuzzer harness for the mp4dump code path.
//
// mp4dump (Source/C++/Apps/Mp4Dump/Mp4Dump.cpp) parses an MP4 file by looping
// AP4_DefaultAtomFactory::CreateAtomFromStream + AP4_Atom::Inspect over the input stream.
// This harness drives that EXACT path over the fuzzed bytes (input wrapped in an
// AP4_MemoryByteStream, inspector output sent to an in-memory stream instead of stdout).
//
// Rationale (rlenv rule 5): as a raw file-input CLI target, the ASan-instrumented mp4dump
// binary defeats Mayhem's coverage phase (empty optimized set => edges_covered=0 despite
// productive fuzzing). Converting to an in-process, SanitizerCoverage-instrumented libFuzzer
// harness over the same parse loop restores stable edge coverage.
#include <stdint.h>
#include <stddef.h>

#include "Ap4.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    AP4_ByteStream* input  = new AP4_MemoryByteStream(data, (AP4_Size)size);
    AP4_ByteStream* output = new AP4_MemoryByteStream();
    AP4_PrintInspector inspector(*output);
    inspector.SetVerbosity(1);

    AP4_Atom* atom;
    AP4_DefaultAtomFactory atom_factory;
    while (atom_factory.CreateAtomFromStream(*input, atom) == AP4_SUCCESS) {
        AP4_Position position;
        input->Tell(position);
        atom->Inspect(inspector);
        input->Seek(position);
        delete atom;
    }

    output->Release();
    input->Release();
    return 0;
}
