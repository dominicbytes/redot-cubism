# SPDX-License-Identifier: MIT
"""Generate a private build copy of the pinned Framework string implementation."""
import hashlib

PATCH_ID = 'csm-string-defined-hash-v1'
CSM_STRING_SHA256 = '5fd48d1b765d98e79fa9bde762ad5be4ac8d989a41ebe2f1338f0c165deff0d7'


def patch_csm_string(data):
    if hashlib.sha256(data).hexdigest() != CSM_STRING_SHA256:
        raise ValueError('Framework csmString.cpp does not match the reviewed hash patch input')
    text = data.decode('utf-8-sig')
    text = text.replace('#include "csmString.hpp"', '#include "Type/csmString.hpp"\n#include "private/cubism_string_hash.hpp"', 1)
    start = text.index('csmInt32 csmString::CalcHashcode(')
    end = text.index('\nconst csmChar* csmString::GetRawString()', start)
    text = text[:start] + '''csmInt32 csmString::CalcHashcode(const csmChar* c, csmInt32 length)
{
    return cubism_string_hash(c, length, c == GetEmptyString());
}
''' + text[end:]
    return text.encode('utf-8')
