<?php
namespace Modules\ZabbixAIAssistant\Actions;

use CController;
use CControllerResponseData;

class Assistant extends CController {
    private const BACKEND_URL = 'http://127.0.0.1:8091/api/summary';
    private const INTERNAL_KEY_FILE = '/etc/zabbix-ai-assistant/frontend.key';

    protected function checkInput(): bool {
        return $this->validateInput([
            'question' => 'string'
        ]);
    }

    protected function checkPermissions(): bool {
        // Initial rollout is restricted to Zabbix Super Admins.
        // Widen only after implementing and testing role-based authorization.
        return $this->getUserType() == USER_TYPE_SUPER_ADMIN;
    }

    protected function doAction(): void {
        $question = trim((string) $this->getInput('question', ''));
        if ($question === '') {
            $question = 'Summarize and prioritize current unresolved problems. Separate evidence from hypotheses and recommend safe diagnostic checks.';
        }
        if (mb_strlen($question) > 500) {
            $question = mb_substr($question, 0, 500);
        }

        $answer = '';
        $error = '';

        if ($this->hasInput('question')) {
            $key = @file_get_contents(self::INTERNAL_KEY_FILE);
            if ($key === false || trim($key) === '') {
                $error = _('AI backend authentication is not configured.');
            }
            else {
                $ch = curl_init(self::BACKEND_URL);
                $payload = http_build_query(['question' => $question]);
                curl_setopt_array($ch, [
                    CURLOPT_POST => true,
                    CURLOPT_POSTFIELDS => $payload,
                    CURLOPT_HTTPHEADER => [
                        'X-AI-API-Key: '.trim($key),
                        'Content-Type: application/x-www-form-urlencoded'
                    ],
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_CONNECTTIMEOUT => 3,
                    CURLOPT_TIMEOUT => 30,
                    CURLOPT_PROTOCOLS => CURLPROTO_HTTP,
                ]);
                $response = curl_exec($ch);
                $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
                curl_close($ch);

                if ($response === false || $status < 200 || $status >= 300) {
                    $error = _('The AI service is unavailable. Check the assistant service logs.');
                }
                else {
                    $decoded = json_decode($response, true);
                    if (is_array($decoded) && isset($decoded['summary']) && is_string($decoded['summary'])) {
                        $answer = $decoded['summary'];
                    }
                    else {
                        $error = _('The AI service returned an unexpected response.');
                    }
                }
            }
        }

        $this->setResponse(new CControllerResponseData([
            'title' => _('Zabbix AI Assistant'),
            'question' => $question,
            'answer' => $answer,
            'error' => $error
        ]));
    }
}
