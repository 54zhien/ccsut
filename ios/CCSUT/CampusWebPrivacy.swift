import Foundation

enum CampusWebPrivacy {
    /// Presentation only: never change input values or intercept form submissions.
    static let script = #"""
    (() => {
      if (!['ehall.ccsut.cn', 'auth.ccsut.cn'].includes(location.hostname)) return;
      if (window.__ccsutCampusPrivacy) return;
      window.__ccsutCampusPrivacy = true;
      const pattern = /(?<![0-9])[0-9](?:[ \t-]?[0-9]){10,24}[Xx]?(?![0-9])/g;
      function mask() {
        const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (/^(SCRIPT|STYLE|TEXTAREA)$/.test(node.parentElement?.tagName || '')) continue;
          const next = node.nodeValue.replace(pattern, '••••');
          if (next !== node.nodeValue) node.nodeValue = next;
        }
        for (const field of document.querySelectorAll('input, textarea')) {
          pattern.lastIndex = 0;
          const contact = field.type === 'tel' || /phone|mobile|identity|idcard|bank|cert|手机|电话|身份证|银行卡/i.test(
            (field.name || '') + ' ' + (field.placeholder || ''));
          if (contact || pattern.test(field.value || '')) field.style.webkitTextSecurity = 'disc';
        }
      }
      mask();
      new MutationObserver(mask).observe(document.documentElement, {
        subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['value']
      });
      document.addEventListener('input', mask, true);
    })();
    """#
}
