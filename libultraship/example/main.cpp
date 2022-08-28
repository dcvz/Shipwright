#include <stdio.h>
#include <string.h>
#include <libultraship/Archive.h>

int main(int argc, char** argv)
{
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        printf("help text");
    }
    return 0;
}
