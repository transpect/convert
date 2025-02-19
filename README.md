# convert
RESTXQ-based API for transpect conversions

## Configuration

The configuration is stored in `config.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<config xmlns="http://transpect.io/convert">
  <code-dir>/home/letex/convert/converter</code-dir>
  <data-dir>/home/letex/convert/data</data-dir>
  <queue-limit>4</queue-limit>
  <polling-delay>1000</polling-delay>
</config>
```

The converters need to be stored as directory within the path specified by `<code-dir/>`. Each converter directory needs a `Makefile` with the Makefile target `conversion` and the parameters `IN_FILE` and `OUT_DIR`. Considering the example above and a converter named `my-converter`, this would be the resulting path:

```
/home/letex/convert/converter/my-converter/Makefile
```

The input file is specified into the input directory `./in` and the path specified by `<data-dir/>`. The conversion results are stored within the output directory `./out` and the path specified by `<data-dir/>`. For example, for the converter with the name `my-converter` the input and output directory of the file `my-file.xml` would be computed as follows:

```
/home/letex/convert/data/my-converter/my-file.xml/in
/home/letex/convert/data/my-converter/my-file.xml/out
```

The number of parallel conversions are specified with `<queue-limit/>`.

The delay in milliseconds between the queue is polled for a free slot is specified with `<polling-delay/>`.

## Authentification

You can optionally add a SHA-256 hash of an access token to a specific converter by adding its hash and key to generate it to `auth.xml`. A user would then have to add the corresponding HTTP parameter `token` with the appropriate value to their requests.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<auth xmlns="http://transpect.io/convert">
  <converter>
    <name>myconverter</name>
    <token>52199ec32a555bfc682fccdaa92b7d8333278491c395f7b1bef324ef1ccc9e48</token>
    <key>my-secret-key</key>
  </converter>
</auth>
```

## API documentation

### List available converters

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/converters` | GET | | | converter list as JSON object | 

### Convert a file

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/convert` | POST | | | conversion log |
| | | file | File      | |
| | | converter | string   | |
| | | token | string   | |

### Print the conversion queue

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/queue` | GET | | | conversion queue as JSON object | 

### Get the status of a specific conversion

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/list/{$converter}/{$filename}` | GET | | | `pending\|started\|finished` as JSON object |
| | | token | string   | |

### List the conversion results

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/list/{$converter}/{$filename}` | GET | | | JSON object |
| | | token | string   | |

### Download an output file

| URL    | Verb | Parameter | Type | Returns | 
| -------- | ------- | ------- |  ------- | ------- |
| `/download/{$converter}/{$filename}/{$result}` | GET | | | File |
| | | token | string   | |

