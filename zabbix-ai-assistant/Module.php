<?php
namespace Modules\ZabbixAIAssistant;

use APP;
use CMenuItem;
use Zabbix\Core\CModule;

class Module extends CModule {
    public function init(): void {
        APP::Component()->get('menu.main')
            ->findOrAdd(_('Monitoring'))
            ->getSubmenu()
            ->add((new CMenuItem(_('AI Assistant')))
                ->setAction('ai.assistant'));
    }
}
