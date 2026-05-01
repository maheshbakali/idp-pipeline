(function (global) {
  'use strict';

  function escapeHtml(unsafe) {
    return String(unsafe)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function showProcessedPayload(rawText, contentType) {
    var text = (rawText || '').trim();
    if (!text) {
      return { out: '(Empty response body from API.)', summary: '' };
    }

    var data;
    try {
      data = JSON.parse(text);
    } catch (e) {
      return {
        out:
          'Response was not valid JSON (' +
          (contentType || 'unknown type') +
          '):\n\n' +
          text,
        summary: '',
      };
    }

    if (
      data &&
      typeof data === 'object' &&
      !Array.isArray(data) &&
      Object.keys(data).length === 0
    ) {
      return { out: '{}', summary: '' };
    }

    var summary =
      data &&
      data.gptEnrichment &&
      typeof data.gptEnrichment.summary === 'string' &&
      data.gptEnrichment.summary.length
        ? data.gptEnrichment.summary
        : '';

    return { out: JSON.stringify(data, null, 2), summary: summary };
  }

  function IdpUploadWidget(props) {
    var React = global.React;
    var useMemo = React.useMemo;
    var useRef = React.useRef;
    var useState = React.useState;

    var cfg = props || {};
    var endpoints = cfg.endpoints || {};
    var uploadUrl = endpoints.uploadUrl || '/documents/upload';
    var byUploadUrl =
      endpoints.byUploadUrl || function (uploadId) { return '/documents/by-upload/' + encodeURIComponent(uploadId); };

    var maxAttempts = typeof cfg.maxAttempts === 'number' ? cfg.maxAttempts : 90;
    var delayMs = typeof cfg.delayMs === 'number' ? cfg.delayMs : 2000;

    var initialDocType = typeof cfg.initialDocType === 'string' ? cfg.initialDocType : 'invoice';

    var _a = useState(initialDocType), docType = _a[0], setDocType = _a[1];
    var _b = useState(null), file = _b[0], setFile = _b[1];
    var _c = useState(false), submitting = _c[0], setSubmitting = _c[1];
    var _d = useState(''), msgText = _d[0], setMsgText = _d[1];
    var _e = useState(false), msgIsError = _e[0], setMsgIsError = _e[1];
    var _f = useState(''), outText = _f[0], setOutText = _f[1];
    var _g = useState(''), summary = _g[0], setSummary = _g[1];
    var _h = useState(false), resultVisible = _h[0], setResultVisible = _h[1];

    var abortRef = useRef(null);

    var accept = useMemo(function () {
      return '.pdf,.png,.jpg,.jpeg,image/png,image/jpeg,application/pdf';
    }, []);

    function setError(message) {
      setMsgIsError(true);
      setMsgText(message || '');
    }

    function setStatus(message) {
      setMsgIsError(false);
      setMsgText(message || '');
    }

    function resetResult() {
      setResultVisible(false);
      setOutText('');
      setSummary('');
    }

    async function poll(uploadId, signal) {
      for (var i = 0; i < maxAttempts; i++) {
        var r = await fetch(byUploadUrl(uploadId), { signal: signal });
        if (r.ok) {
          var raw = await r.text();
          var rendered = showProcessedPayload(raw, r.headers.get('content-type'));
          setOutText(rendered.out);
          setSummary(rendered.summary);
          setResultVisible(true);
          setStatus('Processing complete.');
          return;
        }

        if (r.status !== 404) {
          var t = await r.text();
          throw new Error(t || r.statusText);
        }

        setStatus('Waiting for processing… (' + (i + 1) + '/' + maxAttempts + ')');
        await new Promise(function (res) { return setTimeout(res, delayMs); });
      }

      setMsgIsError(true);
      setMsgText('Timed out waiting for processing. Check Azure Function logs and Cosmos DB.');
    }

    async function onSubmit(e) {
      e.preventDefault();
      if (submitting) return;
      if (!file) return;

      if (abortRef.current) {
        try { abortRef.current.abort(); } catch (_) {}
      }
      abortRef.current = new AbortController();

      setMsgText('');
      setMsgIsError(false);
      resetResult();
      setSubmitting(true);

      var fd = new FormData();
      fd.append('docType', docType);
      fd.append('file', file);

      try {
        var res = await fetch(uploadUrl, { method: 'POST', body: fd, signal: abortRef.current.signal });
        var body = await res.json().catch(function () { return {}; });
        if (!res.ok) {
          throw new Error(body.message || res.statusText || String(res.status));
        }
        setStatus(body.message || 'Uploaded.');
        await poll(body.uploadId, abortRef.current.signal);
      } catch (err) {
        if (err && err.name === 'AbortError') {
          setError('Request cancelled.');
        } else {
          setError((err && err.message) || String(err));
        }
      } finally {
        setSubmitting(false);
      }
    }

    return React.createElement(
      React.Fragment,
      null,
      React.createElement('h1', null, 'Upload document'),
      React.createElement(
        'p',
        { className: 'status' },
        'PDF, PNG, or JPEG — max 5\u00A0MB. After upload, processing runs in Azure; results appear below when ready.'
      ),
      React.createElement(
        'div',
        { className: 'card' },
        React.createElement(
          'form',
          { onSubmit: onSubmit },
          React.createElement('label', { htmlFor: 'docType' }, 'Document type'),
          React.createElement(
            'select',
            {
              id: 'docType',
              name: 'docType',
              required: true,
              value: docType,
              onChange: function (ev) { return setDocType(ev.target.value); },
              disabled: submitting,
            },
            React.createElement('option', { value: 'invoice' }, 'Invoice'),
            React.createElement('option', { value: 'receipt' }, 'Receipt'),
            React.createElement('option', { value: 'contract' }, 'Contract'),
            React.createElement('option', { value: 'other' }, 'Other')
          ),
          React.createElement('label', { htmlFor: 'file' }, 'File'),
          React.createElement('input', {
            id: 'file',
            name: 'file',
            type: 'file',
            accept: accept,
            required: true,
            disabled: submitting,
            onChange: function (ev) {
              var f = ev.target && ev.target.files ? ev.target.files[0] : null;
              setFile(f || null);
            },
          }),
          React.createElement(
            'button',
            { type: 'submit', disabled: submitting || !file },
            submitting ? 'Uploading…' : 'Upload'
          )
        ),
        React.createElement(
          'div',
          {
            className: 'status' + (msgIsError ? ' err' : ''),
            dangerouslySetInnerHTML: {
              __html: msgText
                ? msgIsError
                  ? '<span class="err">' + escapeHtml(msgText) + '</span>'
                  : escapeHtml(msgText)
                : '',
            },
          }
        )
      ),
      React.createElement(
        'div',
        { className: 'card', hidden: !resultVisible },
        React.createElement('h2', { style: { fontSize: '1rem', marginTop: 0 } }, 'Processed document'),
        React.createElement(
          'p',
          { className: 'status', hidden: !summary, style: { marginTop: 0 } },
          summary
        ),
        React.createElement('pre', null, outText)
      )
    );
  }

  global.IdpUploadWidget = IdpUploadWidget;
})(window);

