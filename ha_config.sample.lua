-- Copie este arquivo para ha_config.lua e preencha.
-- ha_config.lua é gitignored, então seu token/segredo nunca é commitado.
return {
    host = "homeassistant.99lab.online",
    port = 443,
    https = true,  -- true se o HA usa HTTPS; recomendado fora da LAN confiável

    -- MODO 1 (recomendado): integração nativa via webhook.
    -- Pegue a URL no HA ao adicionar a integração KOReader; cole só o id final aqui.
    -- Ex.: URL = https://.../api/webhook/AbC123  ->  webhook_id = "AbC123"
    webhook_id = "ColeSeuWebhookIdAqui",

    -- MODO 2 (legado): REST /api/states com token de longa duração.
    -- Usado só se webhook_id estiver vazio. Deixe o token vazio se for usar webhook.
    token = "",
}
