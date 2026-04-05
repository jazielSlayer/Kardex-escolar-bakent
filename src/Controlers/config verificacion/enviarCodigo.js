import transporter from "./mailer.js";
import smsClient   from "./sms.js";

// ── Enviar código por email ───────────────────────────────────
export const enviarEmail = async (destino, codigo) => {
  await transporter.sendMail({
    from:    process.env.MAIL_FROM,
    to:      destino,
    subject: "Código de verificación — Sistema Escolar",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: auto;">
        <div style="background: linear-gradient(135deg,#667eea,#764ba2);
                    padding: 24px; border-radius: 10px 10px 0 0; text-align: center;">
          <h2 style="color:white; margin:0;">Verificación en dos pasos</h2>
        </div>
        <div style="background:#fff; padding:32px; border:1px solid #e0e0e0;
                    border-radius: 0 0 10px 10px;">
          <p style="color:#555; font-size:15px;">
            Usa el siguiente código para completar tu inicio de sesión.
            Es válido por <strong>10 minutos</strong>.
          </p>
          <div style="text-align:center; margin: 28px 0;">
            <span style="font-size: 40px; font-weight: bold; letter-spacing: 10px;
                         color: rgb(126,99,148);">${codigo}</span>
          </div>
          <p style="color:#999; font-size:12px; text-align:center;">
            Si no solicitaste este código, ignora este mensaje.
            Nunca compartas tu código con nadie.
          </p>
        </div>
      </div>
    `,
  });
};

// ── Enviar código por SMS (Twilio) ────────────────────────────
export const enviarSMS = async (destino, codigo) => {
  await smsClient.messages.create({
    from: process.env.TWILIO_PHONE,
    to:   destino,
    body: `Tu código de verificación del Sistema Escolar es: ${codigo}. Válido por 10 minutos. No lo compartas con nadie.`,
  });
};