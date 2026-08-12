    function parseQuality(accept, mediaType) {
        var bestQuality = 0;
        var bestSpecificity = -1;
        var entries = accept.split(',');
        var baseType = mediaType.split('/')[0];
        for (var index = 0; index < entries.length; index++) {
            var parts = entries[index].trim().toLowerCase().split(';');
            var type = parts[0].trim();
            var quality = 1;
            for (var parameterIndex = 1; parameterIndex < parts.length; parameterIndex++) {
                var parameter = parts[parameterIndex].trim().split('=');
                if (parameter[0] === 'q') {
                    quality = Number(parameter[1]);
                    if (!isFinite(quality)) {
                        quality = 0;
                    }
                }
            }
            var specificity = -1;
            if (type === mediaType) {
                specificity = 2;
            } else if (type === baseType + '/*') {
                specificity = 1;
            } else if (type === '*/*') {
                specificity = 0;
            }
            if (
                specificity >= 0 &&
                (specificity > bestSpecificity ||
                    (specificity === bestSpecificity && quality > bestQuality))
            ) {
                bestSpecificity = specificity;
                bestQuality = quality;
            }
        }
        return bestQuality;
    }

    var accept = headers.accept ? headers.accept.value : '';
    var markdownQuality = parseQuality(accept, 'text/markdown');
    var htmlQuality = parseQuality(accept, 'text/html');
    headers['x-md'] = {value: markdownQuality > 0 && markdownQuality > htmlQuality ? '1' : '0'};
