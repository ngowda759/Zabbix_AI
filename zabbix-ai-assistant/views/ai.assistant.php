<?php
$page = new CHtmlPage();
$page->setTitle(_('Zabbix AI Assistant'));

$form = (new CForm('post', 'zabbix.php'))
    ->addItem(new CVar('action', 'ai.assistant'))
    ->addItem(
        (new CLabel(_('Ask about current monitoring problems'), 'question'))
            ->addItem(
                new CTextArea('question', $data['question'], [
                    'rows' => 3,
                    'maxlength' => 500
                ])
            )
    )
    ->addItem(new CSubmit(_('Analyze current problems')))
    ->addItem(
        new CTag('p', true,
            _('Read-only: this assistant does not acknowledge problems or change monitoring configuration.')
        )
    );

$container = (new CDiv())->addClass('zi-ai-assistant');
$container->addItem($form);

if ($data['error'] !== '') {
    $container->addItem((new CDiv($data['error']))->addClass('msg-bad'));
}

if ($data['answer'] !== '') {
    $container->addItem(
        (new CDiv())->addClass('zi-ai-answer')->addItem([
            new CTag('h3', true, _('AI analysis')),
            new CTag('pre', true, $data['answer'])
        ])
    );
}

$page->addItem($container)->show();
