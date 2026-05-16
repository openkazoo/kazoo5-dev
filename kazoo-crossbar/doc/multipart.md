# Sending data in HTTP

There are multiple ways to sending data in HTTP protocol and we are not going to deep explaining all of them. This writing is just a very
quick cheat sheet describing some specific needs to help in times we stuck.

This section tries to describes things in general you may need to read the endpoint documentation first for any specific options or work flow.

Sending data in HTTP protocol is possible with HTTP methods like `PUT`, `POST`, `PATCH` and `DELETE`. Another important part of the request is setting
the correct HTTP headers like `Content-Type` which specifies how the server (in this case Kazoo) should interpret the payload.

The main content in Kazoo is `application/json`. This indicates the payload is JSON data structure in plain text.

Another most common content type (or encoding) is `text/plain`. You may see this in Kazoo Notification API endpoint when you are trying to fetch or update
the notification plain text template attachments.

The rest content types are either binary data like `image/png` or `audio/mp3` or etc... . There are multiple way to send binary data see read below to learn more.

Kazoo also supports `application/base64` content type. This type is handy to upload very small image files like icon and logo.

## Different ways to send data

### Uploading JSON data

#### Send JSON data as `application/json`

This is best way to send JSON data to Kazoo. The payload is JSON as plain text with HTTP header set to `application/json`.

Here is an example plain text of a HTTP request with `application/x-www-form-urlencoded`:

```
PUT /account HTTP/1.1
Host: foo.example
Content-Type: application/json
Content-Length: 45

{"status":"success","request_id":"12ehqwe23"}
```

Example using `cuRL` to send JSON data (note setting the HTTP header using `-H` option, and data with `-d`):

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data": {"billing_mode": "manual","call_restriction": {},"caller_id": {},"created": 63621662701,"dial_plan": {},"enabled": true,"is_reseller": false,"language": "en-us","music_on_hold": {},"name": "child account","preflow": {},"realm": "aeac33.sip.2600hz.com","reseller_id": "undefined","ringtones": {},"some_key":"some_value","superduper_admin": false,"timezone": "America/Los_Angeles","wnm_allow_additions": false}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

#### Send JSON data as `application/x-www-form-urlencoded` HTTP encoding

This is the default way of uploading or submitting HTML forms in which the keys and values are encoded in key-value tuples
separated by `&`, with a `=` between the key and the value.

!!! warning
    Non-alphanumeric characters in both keys and values are percent encoded, this is the reason why this type is not very suitable
    to use with binary data in that case use `multipart/form-data` or other methods described here.

Here is an example plain text of a HTTP request with `application/x-www-form-urlencoded`:

```
POST /test HTTP/1.1
Host: foo.example
Content-Type: application/x-www-form-urlencoded
Content-Length: 27

field1=value1&field2=value2
```

If you're using cURL command line, this is the default `Content-Type` if you don't specify it manually.

### Sending data as `multipart/form-data`

This is another popular way to upload form data from HTML, each value is sent as a block of data ("body part"), with a user agent-defined
delimiter ("boundary") separating each part. The keys are given in the `Content-Disposition` header of each part.

You can also add other HTTP headers in each part, this can be useful to upload multiple files of different type
(also see [multipart/mixed](sending-data-as-multipart-mixed) section below).

Here is an example plain text of a HTTP request with `application/x-www-form-urlencoded`:

Also read [Setting transfer encoding type](setting-transfer-encoding-type-with-content-transfer-encoding).

```
POST /test HTTP/1.1
Host: foo.example
Content-Type: multipart/form-data; boundary=------------------------boundary

--------------------------boundary
Content-Disposition: form-data; filename="image.png"
Content-Type: image/png

image.png binary data
--------------------------boundary--
```

**Execute the cURL request**

cUrl command to send logo

* `-H` or `--header` to set HTTP header
* `-F` `--form` to specify the key-value data, here the key is `file` and value is content of file `image.png`.
    * `key=value` is how you specify form data
    * `key=@value`: `@` here specifies the rest is the path to the file to read the content and use it as `key` value.
    * `type=image/png`: is specifying the content type of this part, otherwise default to file's content type detected by cURL
    * `filename=logo.png`: if you want to set a customize filename in the header, otherwise default to the actual file name

For more information on cURL options please read its manual (`man curl`).

```shell
curl -v -X PUT -i \
    -H 'X-Auth-Token: {AUTH_TOKEN}' \
    -H "Content-Type: multipart/form-data" \
    -F "file=@{image.png};type=image/png;filename=logo.png" \
    http://{SERVER}/v2/whitelabel/{DOMAIN}/logo
```

!!! note
    You can drop `-H "Content-Type: multipart/form-data"`, this is the default option in curl when using `-F` (or `--form`)

### Sending data as `multipart/mixed`

This is the best and recommended way to send multiple file.

`multipart/mixed` is used for sending files with different Content-Type header fields inline (or as attachments).

Also read [Setting transfer encoding type](setting-transfer-encoding-type-with-content-transfer-encoding).

!!! note
    The default content-type for each part is "text/plain". So don't forget to set content-type header!

The request is almost identcal to `multipart/form-data` but the HTTP header `content-type: multipart/mixed`

```
POST /test HTTP/1.1
Host: foo.example
Content-Type: multipart/mixed;boundary="boundary"

--------------------------boundary
content-disposition: form-data; filename="image.png"
content-type: image/png

image.png binary data
--------------------------boundary--
```

**Example execute the cURL request**

Sending Multi-part Outgoing Faxes Request:

```shell
curl -v -X PUT -i \
    -H 'X-Auth-Token: {AUTH_TOKEN}' \
    -H "Content-Type: multipart/mixed" \
    -F "content=@{FILE.json}; type=application/json" \
    -F "content=@{FILE.pdf}; type=application/pdf" \
    http://{SERVER}/v2/accounts/{ACCOUNT_ID}/faxes/outgoing
```

!!! note
    See [multipart/form-data](sending-data-as-multipart-form-data) for cURL command options details.

### Send data as `application/base64`

This is another way to send data (binary or JSON) to Kazoo. Base64 is a text encoding mechanism, [RFC 4648](http://tools.ietf.org/html/rfc4648). This is useful to send very small files in plain text, like icon or logo. For bigger files it is better to use binary method or `multipart/mixed`.

For using this method you have to set `Content-Type: application/base64` and send body part in Base64 encoded plain text.

You can send the actual Base64 text representation as body or prefix it with some standard headers based on [RFC 2397](http://tools.ietf.org/rfc/rfc2397.txt).

```
data:[<mediatype>][;base64],<data>
```

For example:

```
data:base64;image/png,{BASE64-ENCODED IMAGE DATA}
```

Here is an example plain text of a HTTP request with `application/base64`:

```
POST /test HTTP/1.1
Host: foo.example
Content-Type: application/base64"

data:base64;image/png,{BASE64-ENCODED IMAGE DATA}
```

**Example execute the cURL request**

```shell
curl -v -X PUT -i \
    -H 'X-Auth-Token: {AUTH_TOKEN}' \
    -H "Content-Type: application/base64" \
    -d "data:base64;image/png,{BASE64-ENCODED IMAGE DATA}" \
    http://{SERVER}/v2/whitelabel/{DOMAIN}/logo
```

## Notes

### Setting transfer encoding type with `Content-Transfer-Encoding`

When using `multipart/form-data` or `multipart/mixed` methods to send data, you can encode a part in different way than its actual
content type.

For example when sending a PNG image, instead if sending that part as binary you can encode it to Base64 and setting this header,
so the HTTP server then first converts this part from Base64 to the original content type then uses the data as-is.

Here is an example:

```shell
curl -v -X PUT -i \
    -H 'X-Auth-Token: {AUTH_TOKEN}' \
    -H "Content-Type: multipart/form-data" \
    -F "file=@{image.png};encoder=base64" \
    http://{SERVER}/v2/whitelabel/{DOMAIN}/logo

POST /test HTTP/1.1
Host: foo.example
Content-Type: multipart/form-data; boundary=------------------------boundary

--------------------------boundary
Content-Disposition: form-data; filename="image.png"
Content-Transfer-Encoding: base64
Content-Type: image/png

{BASE64-ENCODED IMAGE DATA}
--------------------------boundary--
```

Here `encoder=base64` specifies that cURL should read the file content, convert it to Base64 and send it.

## Examples

### Sending Multi-part Outgoing Faxes Request

With multi part you can create an outgoing fax request and upload the document to fax (e.g.: a PDF file) at the same time.

**Create a JSON file for the outgoing fax options**

```json
{
    "data": {
        "retries": 3,
        "from_name": "Fax Sender",
        "from_number": "{FROM_NUMBER}",
        "to_name": "Fax Recipient",
        "to_number": "{TO_NUMBER}",
        "fax_identity_number": "{ID_NUMBER}",
        "fax_identity_name": "Fax Header"
    }
}
```

**Execute the cURL request**

```shell
curl -v -X PUT -i \
    -H 'X-Auth-Token: {AUTH_TOKEN}' \
    -H "Content-Type: multipart/mixed" \
    -F "content=@{FILE.json}; type=application/json" \
    -F "content=@{FILE.pdf}; type=application/pdf" \
    http://{SERVER}/v2/accounts/{ACCOUNT_ID}/faxes/outgoing
```

