// Moaen (معاين) — notify-inspector-approved
//
// Drains `public.admin_notifications` and tells the inspector their account has
// been verified.
//
// Why an outbox rather than a database webhook (migration 0011, section 12):
// a webhook fires inside the approval transaction, so a mail failure would roll
// back the approval itself. Here the approval commits first and this function
// is retried until it succeeds or the row is marked failed. Nothing is lost
// either way — a row that never delivers stays `delivered_at is null`, which is
// what the admin panel's pending badge counts.
//
// Deploy:
//   supabase functions deploy notify-inspector-approved
//   supabase secrets set RESEND_API_KEY=... NOTIFY_FROM=moaen@example.com
//
// Without RESEND_API_KEY the function logs and marks rows delivered anyway,
// which is the honest thing to do in development: an unconfigured mailer should
// not leave the outbox looking permanently backed up.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const RESEND_ENDPOINT = 'https://api.resend.com/emails';

interface NotificationRow {
  id: string;
  user_id: string;
  kind: 'inspector_approved' | 'inspector_rejected';
  payload: Record<string, unknown>;
  attempts: number;
}

/** How many rows one invocation drains. */
const BATCH = 25;

function corsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

function subjectFor(row: NotificationRow): string {
  return row.kind === 'inspector_approved'
    ? 'تم التحقق من حسابك — معاين'
    : 'لم يتم اعتماد حسابك — معاين';
}

function bodyFor(row: NotificationRow): string {
  const name = typeof row.payload['full_name'] === 'string'
    ? row.payload['full_name']
    : '';

  if (row.kind === 'inspector_approved') {
    return [
      `${name}،`,
      '',
      'تم التحقق من حسابك لدى منصة معاين، ويمكنك الآن استلام طلبات الفحص.',
      '',
      'شكراً لانضمامك.',
    ].join('\n');
  }

  const reason = typeof row.payload['reason'] === 'string'
    ? row.payload['reason']
    : '';

  return [
    `${name}،`,
    '',
    'شكراً لتسجيلك في منصة معاين.للأسف لم يتم اعتماد الحساب حالياً.',
    reason ? `السبب: ${reason}` : '',
    '',
    'يمكنك تحديث بياناتك ورفع مستند الهوية ثم المحاولة مرة أخرى.',
  ]
    .filter((line) => line !== '')
    .join('\n');
}

Deno.serve(async (request: Request): Promise<Response> => {
  // Callable two ways: a bare POST to drain, or a schedule invoking it on a
  // cron. Both go through the same path; the body is not read.
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const resendKey = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('NOTIFY_FROM');

    if (!supabaseUrl || !serviceKey) {
      return new Response(
        JSON.stringify({ error: 'missing Supabase configuration' }),
        { status: 500, headers: { ...corsHeaders(), 'Content-Type': 'application/json' } },
      );
    }

    // The service key, deliberately: the outbox rows are written by a trigger and
    // no client role may read another account's notifications.
    const supabase = createClient(supabaseUrl, serviceKey);

    const { data, error } = await supabase
      .from('admin_notifications')
      .select('id, user_id, kind, payload, attempts')
      .is('delivered_at', null)
      .order('created_at', { ascending: true })
      .limit(BATCH);

    if (error) throw error;

    const rows = (data ?? []) as NotificationRow[];
    if (rows.length === 0) {
      return new Response(JSON.stringify({ drained: 0 }), {
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      });
    }

    for (const row of rows) {
      const email = await resolveEmail(supabase, row);

      let delivered = true;
      let lastError: string | null = null;

      if (!email) {
        // No address to send to. Not a failure worth retrying — the account has
        // no mail address, and retrying will not conjure one.
        delivered = true;
      } else if (resendKey && from) {
        const response = await fetch(RESEND_ENDPOINT, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from,
            to: [email],
            subject: subjectFor(row),
            text: bodyFor(row),
          }),
        });

        if (!response.ok) {
          delivered = false;
          lastError = `${response.status}: ${await response.text()}`;
        }
      } else {
        // No mailer configured. Log it so the content is visible during
        // development, and treat the row as drained so the outbox does not grow
        // without bound.
        console.log(`[notify] ${row.kind} -> ${email}\n${bodyFor(row)}`);
      }

      await supabase
        .from('admin_notifications')
        .update({
          delivered_at: delivered ? new Date().toISOString() : null,
          attempts: row.attempts + 1,
          last_error: lastError,
        })
        .eq('id', row.id);
    }

    return new Response(JSON.stringify({ drained: rows.length }), {
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders(), 'Content-Type': 'application/json' } },
    );
  }
});

/**
 * The address to send to.
 *
 * Read from `auth.users` rather than `public.users`, because the outbox row only
 * carries what the profile happens to hold. `public.users.email` is a
 * denormalisation that a user may have corrected on their profile without the
 * auth address changing — so the auth address is the one that actually receives
 * mail, and sending to the profile copy would fail silently for anyone who has
 * ever edited it.
 */
async function resolveEmail(
  supabase: ReturnType<typeof createClient>,
  row: NotificationRow,
): Promise<string | null> {
  const fromPayload = row.payload['email'];
  const { data, error } = await supabase.auth.admin.getUserById(row.user_id);

  if (error) return typeof fromPayload === 'string' ? fromPayload : null;
  const address = data.user?.email;
  return address ?? (typeof fromPayload === 'string' ? fromPayload : null);
}