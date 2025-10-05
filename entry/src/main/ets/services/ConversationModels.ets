/**
 * 对话记录模型
 */
export class Conversation {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
  isActive: boolean;

  constructor(title: string = '新对话') {
    this.id = this.generateId();
    this.title = title;
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
    this.messageCount = 0;
    this.isActive = false;
  }

  private generateId(): string {
    return 'conv_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  updateTitle(newTitle: string): void {
    this.title = newTitle;
    this.updatedAt = Date.now();
  }

  updateActivity(): void {
    this.updatedAt = Date.now();
  }

  incrementMessageCount(): void {
    this.messageCount++;
    this.updatedAt = Date.now();
  }
}
