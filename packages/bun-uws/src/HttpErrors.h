/*
 * Authored by Alex Hultman, 2018-2023.
 * Intellectual property of third-party.

 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at

 *     http://www.apache.org/licenses/LICENSE-2.0

 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <string_view>

namespace uWS {
/* Possible errors from http parsing */
enum HttpError {
    HTTP_ERROR_505_HTTP_VERSION_NOT_SUPPORTED = 1,
    HTTP_ERROR_431_REQUEST_HEADER_FIELDS_TOO_LARGE = 2,
    HTTP_ERROR_400_BAD_REQUEST = 3
};


/* Anonymized pages */
static const std::string_view httpErrorResponses[] = {
    "", /* Zeroth place is no error so don't use it */
    "HTTP/1.1 505 HTTP Version Not Supported\r\nConnection: close\r\n\r\n",
    "HTTP/1.1 431 Request Header Fields Too Large\r\nConnection: close\r\n\r\n",
    "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
};



}
