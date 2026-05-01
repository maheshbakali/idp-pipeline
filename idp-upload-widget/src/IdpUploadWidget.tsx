import React, { useCallback, useMemo, useRef, useState } from 'react'

export type DocType = 'invoice' | 'receipt' | 'contract' | 'other' | (string & {})

export type IdpUploadWidgetEndpoints = {
  /**
   * Upload endpoint that accepts multipart form data:
   * - docType: string
   * - file: File
   */
  uploadUrl?: string
  /**
   * Poll endpoint that returns 404 while processing and 200 with the final JSON when ready.
   * If provided as string, it is treated as a prefix and the uploadId is appended URL-encoded.
   */
  byUploadUrl?:
    | string
    | ((uploadId: string) => string)
}

export type IdpUploadWidgetProps = {
  endpoints?: IdpUploadWidgetEndpoints
  initialDocType?: DocType
  maxAttempts?: number
  delayMs?: number
  accept?: string
  className?: string
  style?: React.CSSProperties
  onComplete?: (payload: unknown) => void
}

function parseProcessedPayload(rawText: string, contentType: string | null) {
  const text = (rawText ?? '').trim()
  if (!text) {
    return { out: '(Empty response body from API.)', summary: '', json: null as unknown }
  }

  let data: unknown
  try {
    data = JSON.parse(text) as unknown
  } catch {
    return {
      out: `Response was not valid JSON (${contentType || 'unknown type'}):\n\n${text}`,
      summary: '',
      json: null as unknown,
    }
  }

  if (
    data &&
    typeof data === 'object' &&
    !Array.isArray(data) &&
    Object.keys(data as Record<string, unknown>).length === 0
  ) {
    return { out: '{}', summary: '', json: data }
  }

  const summary =
    typeof (data as any)?.gptEnrichment?.summary === 'string' &&
    (data as any).gptEnrichment.summary.length
      ? ((data as any).gptEnrichment.summary as string)
      : ''

  return { out: JSON.stringify(data, null, 2), summary, json: data }
}

const styles = {
  page: {
    fontFamily: 'system-ui, sans-serif',
    color: '#1a1a1a',
    background: '#f4f6f9',
    maxWidth: '52rem',
    margin: '2rem auto',
    padding: '0 1rem',
  } satisfies React.CSSProperties,
  h1: {
    fontSize: '1.35rem',
    fontWeight: 600,
    margin: '0 0 0.75rem',
  } satisfies React.CSSProperties,
  card: {
    background: '#fff',
    borderRadius: 8,
    padding: '1.25rem 1.5rem',
    boxShadow: '0 1px 3px rgba(0,0,0,.08)',
    marginBottom: '1rem',
  } satisfies React.CSSProperties,
  label: {
    display: 'block',
    fontSize: '.875rem',
    fontWeight: 500,
    marginBottom: '.35rem',
  } satisfies React.CSSProperties,
  input: {
    width: '100%',
    marginBottom: '1rem',
  } satisfies React.CSSProperties,
  select: {
    width: '100%',
    marginBottom: '1rem',
  } satisfies React.CSSProperties,
  button: {
    background: '#0067b8',
    color: '#fff',
    border: 0,
    padding: '.55rem 1.1rem',
    borderRadius: 6,
    fontWeight: 500,
    cursor: 'pointer',
  } satisfies React.CSSProperties,
  status: {
    fontSize: '.875rem',
    marginTop: '.75rem',
    color: '#444',
  } satisfies React.CSSProperties,
  err: {
    color: '#b00020',
  } satisfies React.CSSProperties,
  pre: {
    background: '#0d1117',
    color: '#e6edf3',
    padding: '1rem',
    borderRadius: 6,
    overflow: 'auto',
    fontSize: '.8rem',
    maxHeight: '28rem',
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  } satisfies React.CSSProperties,
  h2: {
    fontSize: '1rem',
    marginTop: 0,
    marginBottom: '0.25rem',
    fontWeight: 600,
  } satisfies React.CSSProperties,
} as const

export function IdpUploadWidget({
  endpoints,
  initialDocType = 'invoice',
  maxAttempts = 90,
  delayMs = 2000,
  accept = '.pdf,.png,.jpg,.jpeg,image/png,image/jpeg,application/pdf',
  className,
  style,
  onComplete,
}: IdpUploadWidgetProps) {
  const uploadUrl = endpoints?.uploadUrl ?? '/documents/upload'
  const byUpload = endpoints?.byUploadUrl ?? '/documents/by-upload/'

  const byUploadUrl = useCallback(
    (uploadId: string) => {
      if (typeof byUpload === 'function') return byUpload(uploadId)
      return `${byUpload}${encodeURIComponent(uploadId)}`
    },
    [byUpload]
  )

  const [docType, setDocType] = useState<DocType>(initialDocType)
  const [file, setFile] = useState<File | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [msg, setMsg] = useState<string>('')
  const [isError, setIsError] = useState(false)
  const [out, setOut] = useState<string>('')
  const [summary, setSummary] = useState<string>('')
  const [resultVisible, setResultVisible] = useState(false)

  const abortRef = useRef<AbortController | null>(null)

  const isSubmitDisabled = useMemo(() => submitting, [submitting])

  const resetResult = useCallback(() => {
    setResultVisible(false)
    setOut('')
    setSummary('')
  }, [])

  const poll = useCallback(
    async (uploadId: string, signal: AbortSignal) => {
      for (let i = 0; i < maxAttempts; i++) {
        const r = await fetch(byUploadUrl(uploadId), { signal })
        if (r.ok) {
          const raw = await r.text()
          const rendered = parseProcessedPayload(raw, r.headers.get('content-type'))
          setOut(rendered.out)
          setSummary(rendered.summary)
          setResultVisible(true)
          setIsError(false)
          setMsg('Processing complete.')
          onComplete?.(rendered.json)
          return
        }

        if (r.status !== 404) {
          const t = await r.text()
          throw new Error(t || r.statusText)
        }

        setIsError(false)
        setMsg(`Waiting for processing… (${i + 1}/${maxAttempts})`)
        await new Promise((res) => setTimeout(res, delayMs))
      }

      setIsError(true)
      setMsg('Timed out waiting for processing. Check Azure Function logs and Cosmos DB.')
    },
    [byUploadUrl, delayMs, maxAttempts, onComplete]
  )

  const onSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault()

      setMsg('')
      setIsError(false)
      resetResult()
      setSubmitting(true)

      abortRef.current?.abort()
      abortRef.current = new AbortController()

      const fd = new FormData()
      fd.append('docType', String(docType))
      if (file) fd.append('file', file)

      try {
        const res = await fetch(uploadUrl, {
          method: 'POST',
          body: fd,
          signal: abortRef.current.signal,
        })
        const body = (await res.json().catch(() => ({}))) as any
        if (!res.ok) {
          throw new Error(body?.message || res.statusText || String(res.status))
        }
        setIsError(false)
        setMsg(body?.message || 'Uploaded.')
        await poll(body?.uploadId, abortRef.current.signal)
      } catch (err) {
        if ((err as any)?.name === 'AbortError') {
          setIsError(true)
          setMsg('Request cancelled.')
        } else {
          setIsError(true)
          setMsg((err as Error)?.message || String(err))
        }
      } finally {
        setSubmitting(false)
      }
    },
    [docType, file, poll, resetResult, uploadUrl]
  )

  return (
    <div className={className} style={{ ...styles.page, ...style }}>
      <h1 style={styles.h1}>Upload document</h1>
      <p style={{ ...styles.status, marginTop: 0 }}>
        PDF, PNG, or JPEG — max 5&nbsp;MB. After upload, processing runs in Azure;
        results appear below when ready.
      </p>

      <div style={styles.card}>
        <form onSubmit={onSubmit}>
          <label htmlFor="docType" style={styles.label}>
            Document type
          </label>
          <select
            id="docType"
            name="docType"
            required
            value={String(docType)}
            onChange={(e) => setDocType(e.target.value)}
            style={styles.select}
            disabled={submitting}
          >
            <option value="invoice">Invoice</option>
            <option value="receipt">Receipt</option>
            <option value="contract">Contract</option>
            <option value="other">Other</option>
          </select>

          <label htmlFor="file" style={styles.label}>
            File
          </label>
          <input
            id="file"
            name="file"
            type="file"
            accept={accept}
            required
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            style={styles.input}
            disabled={submitting}
          />

          <button type="submit" disabled={isSubmitDisabled} style={styles.button}>
            Upload
          </button>
        </form>

        <div style={styles.status}>
          {msg ? <span style={isError ? styles.err : undefined}>{msg}</span> : null}
        </div>
      </div>

      {resultVisible ? (
        <div style={styles.card}>
          <h2 style={styles.h2}>Processed document</h2>
          {summary ? (
            <p style={{ ...styles.status, marginTop: 0 }}>{summary}</p>
          ) : null}
          <pre style={styles.pre}>{out}</pre>
        </div>
      ) : null}
    </div>
  )
}

