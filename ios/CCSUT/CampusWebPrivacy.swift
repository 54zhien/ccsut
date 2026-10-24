import Foundation

enum CampusWebPrivacy {
    /// Presentation only: never change input values or intercept form submissions.
    static let script = #"""
    (() => {
      if (!['ehall.ccsut.cn', 'auth.ccsut.cn'].includes(location.hostname)) return;
      if (window.__ccsutCampusPrivacy) return;
      window.__ccsutCampusPrivacy = true;
      const pattern = /(?<![0-9])[0-9](?:[ \t-]?[0-9]){10,24}[Xx]?(?![0-9])/g;
      function maskField(field) {
        pattern.lastIndex = 0;
        const contact = field.type === 'tel' || /phone|mobile|identity|idcard|bank|cert|手机|电话|身份证|银行卡/i.test(
          (field.name || '') + ' ' + (field.placeholder || ''));
        if (contact || pattern.test(field.value || '')) field.style.webkitTextSecurity = 'disc';
      }
      // A JS value assignment does not emit DOM mutation or input events.
      for (const type of [HTMLInputElement, HTMLTextAreaElement]) {
        const descriptor = Object.getOwnPropertyDescriptor(type.prototype, 'value');
        if (!descriptor?.get || !descriptor?.set) continue;
        Object.defineProperty(type.prototype, 'value', {
          ...descriptor,
          set(value) { descriptor.set.call(this, value); maskField(this); }
        });
      }
      function block(node) {
        let parent = node.parentElement;
        while (parent && !/^(DIV|P|LI|TD|TH|SECTION|ARTICLE|LABEL|FORM|H[1-6]|BODY|MAIN|HEADER|FOOTER|BUTTON)$/.test(parent.tagName)) {
          parent = parent.parentElement;
        }
        return parent;
      }
      function mask() {
        const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
        const nodes = [];
        let node, previousBlock, combined = '';
        while ((node = walker.nextNode())) {
          if (/^(SCRIPT|STYLE|TEXTAREA)$/.test(node.parentElement?.tagName || '')) continue;
          const currentBlock = block(node);
          if (nodes.length && currentBlock !== previousBlock) combined += '\u0000';
          nodes.push({node, start:combined.length, end:combined.length + node.nodeValue.length});
          combined += node.nodeValue;
          previousBlock = currentBlock;
        }
        pattern.lastIndex = 0;
        for (const match of [...combined.matchAll(pattern)].reverse()) {
          for (const item of nodes) {
            const begin = Math.max(match.index, item.start), end = Math.min(match.index + match[0].length, item.end);
            if (begin >= end) continue;
            const value = item.node.nodeValue;
            item.node.nodeValue = value.slice(0, begin - item.start) + '••••' + value.slice(end - item.start);
          }
        }
        for (const field of document.querySelectorAll('input, textarea')) maskField(field);
      }
      mask();
      new MutationObserver(mask).observe(document.documentElement, {
        subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['value']
      });
      document.addEventListener('input', mask, true);
    })();
    """#
}
