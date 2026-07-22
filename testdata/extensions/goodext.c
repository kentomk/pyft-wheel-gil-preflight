#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyModuleDef_Slot slots[] = {
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},
    {0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "goodext",
    "Original fixture that declares no GIL requirement.",
    0,
    NULL,
    slots,
    NULL,
    NULL,
    NULL,
};

PyMODINIT_FUNC PyInit_goodext(void) {
    return PyModuleDef_Init(&module);
}
