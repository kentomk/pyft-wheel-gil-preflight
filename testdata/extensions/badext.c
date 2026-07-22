#define PY_SSIZE_T_CLEAN
#include <Python.h>

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "badext",
    "Original fixture that intentionally omits a free-threading declaration.",
    -1,
    NULL,
};

PyMODINIT_FUNC PyInit_badext(void) {
    return PyModule_Create(&module);
}
